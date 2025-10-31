variable "folder_id" {
  description = "Folder the service accounts live in and where folder-scoped roles are granted."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "folder_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "cloud_id" {
  description = "Cloud ID, required only when a service account requests cloud-scoped roles."
  type        = string
  default     = null

  validation {
    condition     = var.cloud_id == null || can(regex("^[a-z0-9]{20}$", var.cloud_id))
    error_message = "cloud_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "name_prefix" {
  description = "Prefix prepended to every service account name, so accounts from different stacks do not collide."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "service_accounts" {
  description = <<-EOT
    Service accounts to create, keyed by a short suffix (the account name is `<name_prefix>-<key>`).

    `folder_roles` and `cloud_roles` are granted with the non-authoritative `_iam_member`
    resources, so a grant made outside Terraform on the same folder is left alone.
    Credentials are only materialised when explicitly requested; both are sensitive outputs.
  EOT

  type = map(object({
    description              = optional(string, "Managed by Terraform")
    folder_roles             = optional(list(string), [])
    cloud_roles              = optional(list(string), [])
    create_static_access_key = optional(bool, false)
    create_authorized_key    = optional(bool, false)
  }))

  default = {}

  validation {
    condition     = alltrue([for k in keys(var.service_accounts) : can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", k))])
    error_message = "Service account keys must be lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for sa in var.service_accounts : alltrue([
        for role in concat(sa.folder_roles, sa.cloud_roles) : can(regex("^[a-zA-Z0-9._-]+$", role))
      ])
    ])
    error_message = "Role names must look like Yandex Cloud roles, for example `container-registry.images.puller`."
  }

  validation {
    condition = alltrue([
      for sa in var.service_accounts : !contains(sa.folder_roles, "admin") && !contains(sa.cloud_roles, "admin")
    ])
    error_message = "The `admin` role is refused on purpose: pick the narrowest role that works, or grant it outside this module."
  }

  # Cross-variable validation, available since Terraform 1.9. Catching this here beats
  # a provider error thrown halfway through an apply that has already created accounts.
  validation {
    condition = var.cloud_id != null || alltrue([
      for sa in var.service_accounts : length(sa.cloud_roles) == 0
    ])
    error_message = "cloud_id must be set when any service account requests cloud_roles."
  }
}

variable "authorized_key_algorithm" {
  description = "Key algorithm for generated authorized keys."
  type        = string
  default     = "RSA_4096"

  validation {
    condition     = contains(["RSA_2048", "RSA_4096"], var.authorized_key_algorithm)
    error_message = "authorized_key_algorithm must be RSA_2048 or RSA_4096."
  }
}
