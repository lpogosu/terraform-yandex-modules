variable "cloud_id" {
  description = "Yandex Cloud ID."
  type        = string
}

variable "folder_id" {
  description = "Folder everything is created in."
  type        = string
}

variable "default_zone" {
  description = "Zone the provider uses for resources that do not name one explicitly."
  type        = string
  default     = "ru-central1-a"
}

variable "app_name" {
  description = "Application name. Prefixes the network, the balancer, the database cluster and the bucket."
  type        = string
  default     = "shop"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-22 chars, lowercase letters, digits and hyphens."
  }
}

variable "domain_name" {
  description = "Public host name the balancer serves. A managed certificate is requested for it."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a fully qualified domain name."
  }
}

variable "bucket_name" {
  description = "Globally unique Object Storage bucket name for user uploads."
  type        = string
}

variable "app_backend_ips" {
  description = <<-EOT
    Private IPv4 addresses of the application instances, one entry per instance.
    The instances themselves are out of scope for this example - point this at whatever
    runs the application (a compute instance group, or nodes of an existing cluster).
  EOT

  type = list(object({
    zone       = string
    ip_address = string
  }))

  default = []
}

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

variable "db_password" {
  description = "Password of the application database user. Supply it through a secret store, never in a committed tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters long."
  }
}

variable "db_disk_size" {
  description = "Storage per database host in GB."
  type        = number
  default     = 20
}

variable "labels" {
  description = "Labels applied to every resource."
  type        = map(string)
  default = {
    managed-by = "terraform"
    example    = "web-app"
  }
}
