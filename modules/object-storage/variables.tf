variable "bucket_name" {
  description = "Bucket name. Object Storage names are global, so prefix them with something you own."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = !can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.bucket_name))
    error_message = "bucket_name must not look like an IPv4 address."
  }

  validation {
    condition     = !can(regex("\\.\\.|-\\.|\\.-", var.bucket_name))
    error_message = "bucket_name must not contain `..`, `-.` or `.-`."
  }
}

variable "folder_id" {
  description = "Folder the bucket and its service account belong to."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "folder_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "service_account_name" {
  description = "Name of the service account created for the bucket. Ignored when service_account_id is supplied."
  type        = string
  default     = null

  validation {
    condition     = var.service_account_name == null || can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.service_account_name))
    error_message = "service_account_name must be 3-63 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "service_account_id" {
  description = <<-EOT
    Existing service account to own the bucket. When null the module creates one, grants it
    `service_account_roles` on the folder and issues a static access key for it.
  EOT
  type        = string
  default     = null
}

variable "service_account_roles" {
  description = <<-EOT
    Folder roles granted to the service account the module creates.
    `storage.admin` is the default because the module manages the bucket ACL and policy,
    which `storage.editor` is not allowed to touch. Drop to `storage.editor` when you
    leave both `acl` and `policy` at their defaults.
  EOT
  type        = list(string)
  default     = ["storage.admin"]

  validation {
    condition     = alltrue([for r in var.service_account_roles : startswith(r, "storage.") || startswith(r, "kms.")])
    error_message = "Only storage.* and kms.* roles belong on a bucket service account."
  }
}

variable "acl" {
  description = "Canned ACL applied to the bucket. Anything other than `private` makes bucket contents reachable without credentials."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public-read", "public-read-write", "authenticated-read"], var.acl)
    error_message = "acl must be private, public-read, public-read-write or authenticated-read."
  }
}

variable "policy" {
  description = "Bucket policy as a JSON string. Null leaves the bucket without an explicit policy."
  type        = string
  default     = null

  validation {
    condition     = var.policy == null || can(jsondecode(var.policy))
    error_message = "policy must be valid JSON."
  }
}

variable "anonymous_access_flags" {
  description = "Fine-grained anonymous access. All false keeps the bucket private even if the ACL is loosened."
  type = object({
    read        = optional(bool, false)
    list        = optional(bool, false)
    config_read = optional(bool, false)
  })
  default = {}
}

variable "versioning_enabled" {
  description = "Keep previous versions of overwritten and deleted objects."
  type        = bool
  default     = true
}

variable "default_storage_class" {
  description = "Storage class new objects land in."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "COLD", "ICE"], var.default_storage_class)
    error_message = "default_storage_class must be STANDARD, COLD or ICE."
  }
}

variable "max_size" {
  description = "Hard size limit in bytes. Null means unlimited, which also means an unbounded bill."
  type        = number
  default     = null

  validation {
    condition     = var.max_size == null ? true : var.max_size > 0
    error_message = "max_size must be a positive number of bytes."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete a bucket that still holds objects."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules, keyed by rule id. `prefix` narrows the rule to a key prefix.
    `transitions` moves objects to a colder class after N days; `expiration_days` deletes them.
    With versioning on, `noncurrent_version_expiration_days` is what actually reclaims space.
  EOT

  type = map(object({
    enabled                                = optional(bool, true)
    prefix                                 = optional(string)
    abort_incomplete_multipart_upload_days = optional(number)
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules : alltrue([
        for t in r.transitions : contains(["COLD", "ICE", "STANDARD_IA"], t.storage_class)
      ])
    ])
    error_message = "Lifecycle transitions may only target COLD, ICE or STANDARD_IA."
  }

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      r.expiration_days == null ? true : alltrue([for t in r.transitions : t.days < r.expiration_days])
    ])
    error_message = "Every transition must happen before the object expires."
  }

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      r.expiration_days != null || r.noncurrent_version_expiration_days != null ||
      r.abort_incomplete_multipart_upload_days != null || length(r.transitions) > 0
    ])
    error_message = "A lifecycle rule that neither transitions nor expires anything does nothing."
  }
}

variable "enable_server_side_encryption" {
  description = "Encrypt every object at rest with a KMS key instead of the platform key."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Existing KMS key for server-side encryption. Null makes the module create one."
  type        = string
  default     = null
}

variable "kms_key_rotation_period" {
  description = "Rotation period for the KMS key the module creates, as a Go duration."
  type        = string
  default     = "8760h"

  validation {
    condition     = can(regex("^\\d+h$", var.kms_key_rotation_period))
    error_message = "kms_key_rotation_period must be expressed in whole hours, for example `8760h`."
  }
}

variable "logging" {
  description = "Ship access logs to another bucket. Null disables server access logging."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "access-logs/")
  })
  default = null
}

variable "cors_rules" {
  description = "CORS rules for browser clients. Empty list means the bucket rejects cross-origin requests."
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number, 3600)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.cors_rules : alltrue([
        for m in r.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], upper(m))
      ])
    ])
    error_message = "CORS allowed_methods must be a subset of GET, PUT, POST, DELETE, HEAD."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : !contains(r.allowed_origins, "*") || length(r.allowed_methods) == 1])
    error_message = "A wildcard origin is only allowed together with a single method - usually GET."
  }
}

variable "tags" {
  description = "Tags attached to the bucket."
  type        = map(string)
  default     = {}
}
