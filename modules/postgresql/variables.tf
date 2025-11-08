variable "name" {
  description = "Cluster name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,60}[a-z0-9]$", var.name))
    error_message = "name must be 3-62 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "description" {
  description = "Cluster description."
  type        = string
  default     = "Managed by Terraform"
}

variable "folder_id" {
  description = "Folder the cluster is created in."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "folder_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "network_id" {
  description = "VPC network the cluster hosts are attached to."
  type        = string
}

variable "labels" {
  description = "Labels applied to the cluster."
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "`PRODUCTION` gets the conservative maintenance track, `PRESTABLE` gets updates earlier."
  type        = string
  default     = "PRODUCTION"

  validation {
    condition     = contains(["PRODUCTION", "PRESTABLE"], var.environment)
    error_message = "environment must be PRODUCTION or PRESTABLE."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL major version, for example `16`."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^(1[3-8])(-1c)?$", var.postgresql_version))
    error_message = "postgresql_version must be a supported major version between 13 and 18, optionally with the `-1c` suffix."
  }
}

variable "resource_preset_id" {
  description = "Host class, for example `s3-c2-m8` (2 vCPU / 8 GB) or `c3-c4-m16`."
  type        = string
  default     = "s3-c2-m8"

  validation {
    condition     = can(regex("^[a-z][0-9]+-c[0-9]+-m[0-9]+$", var.resource_preset_id))
    error_message = "resource_preset_id must look like `s3-c2-m8`."
  }
}

variable "disk_size" {
  description = "Storage per host in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size >= 10 && var.disk_size <= 8192
    error_message = "disk_size must be between 10 and 8192 GB."
  }
}

variable "disk_type_id" {
  description = "Storage class. `network-ssd` is the safe default; `local-ssd` and `network-ssd-nonreplicated` need at least three hosts."
  type        = string
  default     = "network-ssd"

  validation {
    condition     = contains(["network-hdd", "network-ssd", "network-ssd-nonreplicated", "local-ssd"], var.disk_type_id)
    error_message = "disk_type_id must be network-hdd, network-ssd, network-ssd-nonreplicated or local-ssd."
  }
}

variable "disk_size_autoscaling" {
  description = <<-EOT
    Automatic storage growth. `disk_size_limit` is the ceiling in GB; the thresholds are percentages
    of current usage. Null disables autoscaling and leaves you with a pager alert instead.
  EOT

  type = object({
    disk_size_limit           = number
    planned_usage_threshold   = optional(number, 70)
    emergency_usage_threshold = optional(number, 85)
  })

  default = null

  validation {
    condition     = var.disk_size_autoscaling == null || try(var.disk_size_autoscaling.disk_size_limit >= var.disk_size, false)
    error_message = "disk_size_limit must be at least as large as disk_size."
  }

  validation {
    condition = var.disk_size_autoscaling == null || try(
      var.disk_size_autoscaling.planned_usage_threshold < var.disk_size_autoscaling.emergency_usage_threshold,
      false
    )
    error_message = "planned_usage_threshold must be lower than emergency_usage_threshold."
  }
}

variable "hosts" {
  description = <<-EOT
    Cluster hosts. One entry per availability zone gives a highly available cluster;
    a single entry gives a cheap single-zone cluster with no automatic failover.
    `priority` biases automatic master election (higher wins).
  EOT

  type = list(object({
    zone             = string
    subnet_id        = string
    assign_public_ip = optional(bool, false)
    priority         = optional(number)
    name             = optional(string)
  }))

  validation {
    condition     = length(var.hosts) > 0
    error_message = "At least one host is required."
  }

  validation {
    condition     = alltrue([for h in var.hosts : can(regex("^ru-central1-[a-d]$", h.zone))])
    error_message = "Host zones must be ru-central1-a, ru-central1-b, ru-central1-c or ru-central1-d."
  }

  # A PRODUCTION cluster in one zone loses its only master together with the zone.
  validation {
    condition = var.environment != "PRODUCTION" || (
      length(var.hosts) >= 2 && length(distinct([for h in var.hosts : h.zone])) >= 2
    )
    error_message = "A PRODUCTION cluster needs at least two hosts spread over at least two availability zones."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the cluster hosts."
  type        = list(string)
  default     = []
}

variable "backup_window_start" {
  description = "UTC time at which the daily full backup starts."
  type = object({
    hours   = number
    minutes = optional(number, 0)
  })
  default = {
    hours = 3
  }

  validation {
    condition     = var.backup_window_start.hours >= 0 && var.backup_window_start.hours <= 23
    error_message = "backup_window_start.hours must be between 0 and 23."
  }

  validation {
    condition     = var.backup_window_start.minutes >= 0 && var.backup_window_start.minutes <= 59
    error_message = "backup_window_start.minutes must be between 0 and 59."
  }
}

variable "backup_retain_period_days" {
  description = <<-EOT
    How long full backups and the WAL archive are kept. This value *is* the point-in-time
    recovery window: Managed Service for PostgreSQL keeps continuous WAL for the same period,
    so a cluster with 7-day retention can be restored to any second within the last 7 days.
  EOT

  type    = number
  default = 7

  validation {
    condition     = var.backup_retain_period_days >= 7 && var.backup_retain_period_days <= 60
    error_message = "backup_retain_period_days must be between 7 and 60."
  }
}

variable "restore" {
  description = <<-EOT
    Point-in-time restore. Set `backup_id` and, optionally, `time` (`YYYY-MM-DDTHH:MM:SS` UTC)
    to build this cluster from an existing backup instead of an empty database.
    Changing it after creation forces a replacement, so leave it null for steady state.
  EOT

  type = object({
    backup_id      = string
    time           = optional(string)
    time_inclusive = optional(bool, false)
  })

  default = null

  validation {
    condition     = var.restore == null || try(var.restore.time, null) == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$", var.restore.time))
    error_message = "restore.time must look like `2025-10-14T21:30:00`."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    Maintenance window. `type = ANYTIME` lets Yandex Cloud restart the cluster whenever it likes;
    `type = WEEKLY` pins the restart to one weekday and hour.
  EOT

  type = object({
    type = optional(string, "ANYTIME")
    day  = optional(string)
    hour = optional(number)
  })

  default = {}

  validation {
    condition     = contains(["ANYTIME", "WEEKLY"], var.maintenance_window.type)
    error_message = "maintenance_window.type must be ANYTIME or WEEKLY."
  }

  validation {
    condition = var.maintenance_window.type != "WEEKLY" ? true : try(
      var.maintenance_window.day != null &&
      var.maintenance_window.hour >= 1 &&
      var.maintenance_window.hour <= 24,
      false
    )
    error_message = "A WEEKLY maintenance window needs a day and an hour between 1 and 24."
  }

  validation {
    condition = var.maintenance_window.day == null ? true : contains(
      ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], var.maintenance_window.day
    )
    error_message = "maintenance_window.day must be one of MON, TUE, WED, THU, FRI, SAT, SUN."
  }
}

variable "access" {
  description = "Which Yandex Cloud services may reach the cluster. Everything is off by default."
  type = object({
    data_lens     = optional(bool, false)
    data_transfer = optional(bool, false)
    serverless    = optional(bool, false)
    web_sql       = optional(bool, false)
  })
  default = {}
}

variable "performance_diagnostics" {
  description = "Statement and session sampling. Sampling intervals are in seconds."
  type = object({
    enabled                      = optional(bool, true)
    sessions_sampling_interval   = optional(number, 60)
    statements_sampling_interval = optional(number, 600)
    advanced_mode                = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.performance_diagnostics.sessions_sampling_interval >= 1 && var.performance_diagnostics.sessions_sampling_interval <= 86400
    error_message = "sessions_sampling_interval must be between 1 and 86400 seconds."
  }

  validation {
    condition     = var.performance_diagnostics.statements_sampling_interval >= 60 && var.performance_diagnostics.statements_sampling_interval <= 86400
    error_message = "statements_sampling_interval must be between 60 and 86400 seconds."
  }
}

variable "pooler_config" {
  description = "Odyssey connection pooler settings. Null keeps the Yandex Cloud defaults (session pooling)."
  type = object({
    pooling_mode = optional(string, "SESSION")
    pool_discard = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.pooler_config == null || contains(["SESSION", "TRANSACTION", "STATEMENT"], try(var.pooler_config.pooling_mode, ""))
    error_message = "pooling_mode must be SESSION, TRANSACTION or STATEMENT."
  }
}

variable "postgresql_config" {
  description = "Raw PostgreSQL settings passed straight to the cluster, for example `{ max_connections = \"200\" }`."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Refuse to delete the cluster. Keep true for anything holding real data."
  type        = bool
  default     = true
}

variable "users" {
  description = <<-EOT
    Users keyed by user name.

    Set `password` for a password you manage yourself, or `generate_password = true` to have
    Yandex Cloud create one and keep it in Connection Manager - in that case the secret never
    reaches Terraform state. `permissions` lists databases the user may connect to;
    `grants` lists roles to hand the user (for example `mdb_monitor`).

    The map itself is deliberately not marked `sensitive`: Terraform refuses a sensitive value
    in `for_each`, and working around that would push `nonsensitive()` through the whole module.
    The provider already marks the user password sensitive, so it stays redacted in plan output.
  EOT

  type = map(object({
    password          = optional(string)
    generate_password = optional(bool, false)
    conn_limit        = optional(number, 50)
    login             = optional(bool, true)
    grants            = optional(list(string), [])
    permissions       = optional(list(string), [])
    settings          = optional(map(string), {})
  }))

  default = {}

  validation {
    condition     = alltrue([for name in keys(var.users) : can(regex("^[a-z][a-z0-9_]{0,62}$", name))])
    error_message = "User names must be lowercase letters, digits and underscores, starting with a letter."
  }

  validation {
    condition     = !contains(keys(var.users), "postgres")
    error_message = "`postgres` is reserved by Managed Service for PostgreSQL and cannot be declared here."
  }

  validation {
    condition = alltrue([
      for u in var.users : (u.password == null) != (u.generate_password == false)
    ])
    error_message = "Each user sets exactly one of `password` or `generate_password = true`."
  }

  validation {
    condition     = alltrue([for u in var.users : u.conn_limit >= 10])
    error_message = "conn_limit below 10 leaves no room for health checks and migrations."
  }
}

variable "databases" {
  description = <<-EOT
    Databases keyed by database name. `owner` must be one of the keys of `var.users`.
    `extensions` are installed into the database at creation time.
  EOT

  type = map(object({
    owner      = string
    lc_collate = optional(string, "C")
    lc_type    = optional(string, "C")
    extensions = optional(list(string), [])
  }))

  default = {}

  validation {
    condition     = alltrue([for name in keys(var.databases) : can(regex("^[a-z][a-z0-9_]{0,62}$", name))])
    error_message = "Database names must be lowercase letters, digits and underscores, starting with a letter."
  }

  # Cross-variable validation (Terraform >= 1.9): an unknown owner otherwise surfaces as a
  # for_each key error deep inside the module.
  validation {
    condition     = alltrue([for db in var.databases : contains(keys(var.users), db.owner)])
    error_message = "Every database owner must be declared in var.users."
  }
}
