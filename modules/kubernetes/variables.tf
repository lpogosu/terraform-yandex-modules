variable "name" {
  description = "Cluster name. Node groups are named `<name>-<node group key>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be 3-42 chars, lowercase letters, digits and hyphens, starting with a letter."
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
  description = "VPC network the cluster and its nodes live in."
  type        = string
}

variable "labels" {
  description = "Labels applied to the cluster and merged into every node group's labels."
  type        = map(string)
  default     = {}
}

variable "service_account_id" {
  description = "Service account the cluster control plane uses (needs k8s.clusters.agent and vpc.publicAdmin)."
  type        = string
}

variable "node_service_account_id" {
  description = "Service account the nodes use (needs container-registry.images.puller at minimum)."
  type        = string
}

variable "master_type" {
  description = "`regional` spreads the control plane over three zones, `zonal` keeps it in one."
  type        = string
  default     = "regional"

  validation {
    condition     = contains(["regional", "zonal"], var.master_type)
    error_message = "master_type must be either `regional` or `zonal`."
  }
}

variable "region" {
  description = "Region used for a regional control plane."
  type        = string
  default     = "ru-central1"
}

variable "master_locations" {
  description = <<-EOT
    Where the control plane lives. Exactly one entry for `zonal`, exactly three for `regional`
    (Yandex Cloud does not offer any other regional layout).
  EOT

  type = list(object({
    zone      = string
    subnet_id = string
  }))

  validation {
    condition     = alltrue([for l in var.master_locations : can(regex("^ru-central1-[a-d]$", l.zone))])
    error_message = "Every master location zone must be one of ru-central1-a, ru-central1-b, ru-central1-c, ru-central1-d."
  }

  validation {
    condition     = length(distinct([for l in var.master_locations : l.zone])) == length(var.master_locations)
    error_message = "Master locations must sit in distinct availability zones."
  }

  # Cross-variable validation (Terraform >= 1.9): the arity depends on master_type,
  # and the provider only reports the mismatch after the plan has been accepted.
  validation {
    condition     = var.master_type != "zonal" || length(var.master_locations) == 1
    error_message = "A zonal control plane takes exactly one master location."
  }

  validation {
    condition     = var.master_type != "regional" || length(var.master_locations) == 3
    error_message = "A regional control plane takes exactly three master locations, one per zone."
  }
}

variable "master_version" {
  description = "Kubernetes minor version for the control plane, for example `1.30`. Null lets the release channel decide."
  type        = string
  default     = null

  validation {
    condition     = var.master_version == null || can(regex("^\\d+\\.\\d+$", var.master_version))
    error_message = "master_version must be a `major.minor` string such as `1.30`."
  }
}

variable "release_channel" {
  description = "Upgrade channel for the control plane."
  type        = string
  default     = "STABLE"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "master_public_ip" {
  description = "Expose the API server on a public address. Keep false and reach the cluster over the VPC where possible."
  type        = bool
  default     = false
}

variable "master_security_group_ids" {
  description = "Security groups attached to the control plane."
  type        = list(string)
  default     = []
}

variable "master_auto_upgrade" {
  description = "Let Yandex Cloud upgrade the control plane inside the maintenance window."
  type        = bool
  default     = true
}

variable "maintenance_windows" {
  description = <<-EOT
    Maintenance windows for the control plane and for node groups that do not override them.
    An empty list means "any time", which is what you want for a non-production cluster and
    almost never what you want for a production one.
  EOT

  type = list(object({
    day        = optional(string)
    start_time = string
    duration   = string
  }))

  default = []

  validation {
    condition = alltrue([
      for w in var.maintenance_windows :
      w.day == null ? true : contains(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], lower(w.day))
    ])
    error_message = "Maintenance window day must be a lowercase English weekday name or null."
  }

  validation {
    condition     = alltrue([for w in var.maintenance_windows : can(regex("^\\d{2}:\\d{2}(:\\d{2})?$", w.start_time))])
    error_message = "Maintenance window start_time must look like `HH:MM` or `HH:MM:SS`."
  }

  validation {
    condition     = alltrue([for w in var.maintenance_windows : can(regex("^\\d+h(\\d+m)?$|^\\d+m$", w.duration))])
    error_message = "Maintenance window duration must look like `3h`, `3h30m` or `90m`."
  }
}

variable "network_policy_provider" {
  description = "Network policy engine. `CALICO` enables NetworkPolicy enforcement, null leaves the cluster without it."
  type        = string
  default     = null

  validation {
    condition     = var.network_policy_provider == null || var.network_policy_provider == "CALICO"
    error_message = "network_policy_provider must be CALICO or null."
  }
}

variable "cluster_ipv4_range" {
  description = "Pod CIDR. Null lets Yandex Cloud pick one; set it explicitly when peering with other networks."
  type        = string
  default     = null

  validation {
    condition     = var.cluster_ipv4_range == null || can(cidrnetmask(var.cluster_ipv4_range))
    error_message = "cluster_ipv4_range must be a valid IPv4 CIDR block."
  }
}

variable "service_ipv4_range" {
  description = "Service CIDR. Null lets Yandex Cloud pick one."
  type        = string
  default     = null

  validation {
    condition     = var.service_ipv4_range == null || can(cidrnetmask(var.service_ipv4_range))
    error_message = "service_ipv4_range must be a valid IPv4 CIDR block."
  }
}

variable "node_ipv4_cidr_mask_size" {
  description = "Size of the pod subnet carved out per node. 24 gives ~110 usable pods, 25 gives ~55."
  type        = number
  default     = 24

  validation {
    condition     = contains([24, 25, 26, 27, 28], var.node_ipv4_cidr_mask_size)
    error_message = "node_ipv4_cidr_mask_size must be one of 24, 25, 26, 27, 28."
  }
}

variable "create_kms_key" {
  description = "Create a KMS symmetric key and use it to encrypt Kubernetes Secrets at rest."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Existing KMS key to encrypt Secrets with. Ignored when create_kms_key is true."
  type        = string
  default     = null

  validation {
    condition     = !(var.create_kms_key && var.kms_key_id != null)
    error_message = "Set either create_kms_key = true or kms_key_id, not both."
  }
}

variable "kms_key_rotation_period" {
  description = "Rotation period for the generated KMS key, as a Go duration."
  type        = string
  default     = "8760h"

  validation {
    condition     = can(regex("^\\d+h$", var.kms_key_rotation_period))
    error_message = "kms_key_rotation_period must be expressed in whole hours, for example `8760h`."
  }
}

variable "master_logging" {
  description = <<-EOT
    Ship control plane logs to Cloud Logging. `log_group_id` null sends them to the folder's
    default log group. Set `enabled = false` to keep the control plane silent.
  EOT

  type = object({
    enabled                    = optional(bool, true)
    log_group_id               = optional(string)
    kube_apiserver_enabled     = optional(bool, true)
    cluster_autoscaler_enabled = optional(bool, true)
    events_enabled             = optional(bool, true)
    audit_enabled              = optional(bool, true)
  })

  default = {}
}

variable "kms_key_deletion_protection" {
  description = <<-EOT
    Refuse to delete the generated KMS key. Losing it makes every Secret in etcd unreadable,
    so this stays true for anything holding real data.
  EOT
  type        = bool
  default     = true
}

variable "node_groups" {
  description = <<-EOT
    Node groups keyed by a short suffix. The key is part of the Terraform address, so renaming a
    key replaces the group while editing its body updates it in place.

    `scale.type` is `fixed` (uses `size`) or `auto` (uses `min`, `max` and `initial`).
    `locations` drives both the allocation policy and the subnets of the node network interface.
  EOT

  type = map(object({
    description = optional(string, "Managed by Terraform")
    version     = optional(string)

    locations = list(object({
      zone      = string
      subnet_id = string
    }))

    platform_id        = optional(string, "standard-v3")
    cores              = optional(number, 2)
    core_fraction      = optional(number, 100)
    memory             = optional(number, 8)
    gpus               = optional(number)
    disk_type          = optional(string, "network-ssd")
    disk_size          = optional(number, 64)
    preemptible        = optional(bool, false)
    nat                = optional(bool, false)
    security_group_ids = optional(list(string), [])
    container_runtime  = optional(string, "containerd")
    metadata           = optional(map(string), {})

    scale = object({
      type    = string
      size    = optional(number)
      min     = optional(number)
      max     = optional(number)
      initial = optional(number)
    })

    labels      = optional(map(string), {})
    node_labels = optional(map(string), {})
    node_taints = optional(list(string), [])

    auto_upgrade    = optional(bool, true)
    auto_repair     = optional(bool, true)
    max_expansion   = optional(number, 1)
    max_unavailable = optional(number, 0)
  }))

  default = {}

  validation {
    condition     = alltrue([for k in keys(var.node_groups) : can(regex("^[a-z][a-z0-9-]{0,20}[a-z0-9]$", k))])
    error_message = "Node group keys must be lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : length(ng.locations) > 0])
    error_message = "Every node group must declare at least one location."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : alltrue([
        for l in ng.locations : can(regex("^ru-central1-[a-d]$", l.zone))
      ])
    ])
    error_message = "Node group location zones must be ru-central1-a, ru-central1-b, ru-central1-c or ru-central1-d."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : contains(["fixed", "auto"], ng.scale.type)])
    error_message = "scale.type must be `fixed` or `auto`."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups :
      ng.scale.type != "fixed" ? true : try(ng.scale.size > 0, false)
    ])
    error_message = "A fixed node group must set scale.size to a positive number."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups :
      ng.scale.type != "auto" ? true : try(ng.scale.min <= ng.scale.max, false)
    ])
    error_message = "An autoscaled node group must set scale.min and scale.max with min <= max."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups :
      ng.scale.type != "auto" || ng.scale.initial == null ? true : try(
        ng.scale.initial >= ng.scale.min && ng.scale.initial <= ng.scale.max, false
      )
    ])
    error_message = "scale.initial must sit between scale.min and scale.max."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : contains([5, 20, 50, 100], ng.core_fraction)])
    error_message = "core_fraction must be 5, 20, 50 or 100 - those are the only guaranteed vCPU shares Yandex Cloud offers."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : contains(["network-hdd", "network-ssd", "network-ssd-nonreplicated"], ng.disk_type)])
    error_message = "disk_type must be network-hdd, network-ssd or network-ssd-nonreplicated."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : ng.disk_size >= 64])
    error_message = "Node boot disks smaller than 64 GB run out of space once images and logs accumulate."
  }

  # A preemptible node is stopped by the platform within 24 hours. Without auto_repair
  # nothing brings it back, and the group silently shrinks to zero.
  validation {
    condition     = alltrue([for ng in var.node_groups : !ng.preemptible || ng.auto_repair])
    error_message = "Preemptible node groups must keep auto_repair enabled, otherwise stopped nodes are never replaced."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : alltrue([
        for t in ng.node_taints : can(regex("^[^=:]+=[^:]*:(NoSchedule|PreferNoSchedule|NoExecute)$", t))
      ])
    ])
    error_message = "Node taints must be written as `key=value:Effect` with effect NoSchedule, PreferNoSchedule or NoExecute."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : contains(["containerd", "docker"], ng.container_runtime)])
    error_message = "container_runtime must be containerd or docker."
  }
}
