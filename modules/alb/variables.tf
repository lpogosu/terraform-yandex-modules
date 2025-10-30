variable "name" {
  description = "Base name. The target group, backend group, router and balancer all derive their names from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be 3-42 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "folder_id" {
  description = "Folder the load balancer and its components are created in."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "folder_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "network_id" {
  description = "VPC network the load balancer is attached to."
  type        = string
}

variable "labels" {
  description = "Labels applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

variable "locations" {
  description = <<-EOT
    Zones the balancer runs in, with the subnet it uses in each. Two zones is the minimum
    that survives losing one; a single zone means the balancer is a single point of failure.
  EOT

  type = list(object({
    zone_id         = string
    subnet_id       = string
    disable_traffic = optional(bool, false)
  }))

  validation {
    condition     = length(var.locations) > 0
    error_message = "At least one location is required."
  }

  validation {
    condition     = alltrue([for l in var.locations : can(regex("^ru-central1-[a-d]$", l.zone_id))])
    error_message = "Location zone_id must be ru-central1-a, ru-central1-b, ru-central1-c or ru-central1-d."
  }

  validation {
    condition     = length(distinct([for l in var.locations : l.zone_id])) == length(var.locations)
    error_message = "Each location must sit in a distinct availability zone."
  }
}

variable "targets" {
  description = <<-EOT
    Backend endpoints, addressed by private IP and subnet. Leave empty when the target group is
    filled from outside Terraform, for example by a Kubernetes ingress controller.
  EOT

  type = list(object({
    subnet_id  = string
    ip_address = string
  }))

  default = []

  validation {
    condition     = alltrue([for t in var.targets : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", t.ip_address))])
    error_message = "Target ip_address must be a plain IPv4 address."
  }
}

variable "backend_port" {
  description = "Port the backends listen on."
  type        = number
  default     = 80

  validation {
    condition     = var.backend_port > 0 && var.backend_port < 65536
    error_message = "backend_port must be between 1 and 65535."
  }
}

variable "backend_http2" {
  description = "Speak HTTP/2 to the backends. Only enable it when the backend actually supports h2c."
  type        = bool
  default     = false
}

variable "backend_weight" {
  description = "Relative weight of the backend inside the backend group."
  type        = number
  default     = 100

  validation {
    condition     = var.backend_weight > 0
    error_message = "backend_weight must be positive."
  }
}

variable "healthcheck" {
  description = <<-EOT
    HTTP health check for the backend group. `interval` and `timeout` are Go durations with a
    unit, for example `1s`. `timeout` must be shorter than `interval`, otherwise checks overlap.
  EOT

  type = object({
    path                = optional(string, "/healthz")
    port                = optional(number)
    interval            = optional(string, "2s")
    timeout             = optional(string, "1s")
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
    expected_statuses   = optional(list(number), [200])
    host                = optional(string)
  })

  default = {}

  validation {
    condition     = startswith(var.healthcheck.path, "/")
    error_message = "healthcheck.path must start with a slash."
  }

  validation {
    condition     = can(regex("^\\d+(\\.\\d+)?s$", var.healthcheck.interval)) && can(regex("^\\d+(\\.\\d+)?s$", var.healthcheck.timeout))
    error_message = "healthcheck.interval and healthcheck.timeout must be given in seconds, for example `2s` or `0.5s`."
  }

  validation {
    condition     = tonumber(replace(var.healthcheck.timeout, "s", "")) < tonumber(replace(var.healthcheck.interval, "s", ""))
    error_message = "healthcheck.timeout must be shorter than healthcheck.interval."
  }

  validation {
    condition     = alltrue([for s in var.healthcheck.expected_statuses : s >= 100 && s <= 599])
    error_message = "healthcheck.expected_statuses must contain valid HTTP status codes."
  }
}

variable "session_affinity" {
  description = "Sticky sessions: `none`, `connection` (client IP) or `cookie`."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "connection", "cookie"], var.session_affinity)
    error_message = "session_affinity must be none, connection or cookie."
  }
}

variable "session_affinity_cookie" {
  description = "Cookie used for sticky sessions. `ttl` is a Go duration; null makes it a session cookie."
  type = object({
    name = optional(string, "alb-affinity")
    ttl  = optional(string)
  })
  default = {}
}

variable "authority" {
  description = "Host names the virtual host answers to. Empty list matches any Host header."
  type        = list(string)
  default     = []
}

variable "routes" {
  description = <<-EOT
    Ordered HTTP routes. The first match wins, so put specific prefixes before `/`.
    An empty list installs a single catch-all route to the backend group.
  EOT

  type = list(object({
    name           = string
    path_prefix    = optional(string, "/")
    path_exact     = optional(string)
    http_methods   = optional(list(string))
    prefix_rewrite = optional(string)
    timeout        = optional(string, "60s")
    idle_timeout   = optional(string)
    upgrade_types  = optional(list(string))
  }))

  default = []

  validation {
    condition     = length(distinct([for r in var.routes : r.name])) == length(var.routes)
    error_message = "Route names must be unique."
  }

  validation {
    condition     = alltrue([for r in var.routes : r.path_exact != null || startswith(r.path_prefix, "/")])
    error_message = "Route path_prefix must start with a slash."
  }
}

variable "public" {
  description = "Expose the balancer on a public IPv4 address. False builds an internal balancer."
  type        = bool
  default     = true
}

variable "internal_address_subnet_id" {
  description = "Subnet holding the internal listener address. Required when `public` is false."
  type        = string
  default     = null

  validation {
    condition     = var.public || var.internal_address_subnet_id != null
    error_message = "internal_address_subnet_id is required for an internal load balancer."
  }
}

variable "reserve_static_ip" {
  description = <<-EOT
    Reserve a static public address and pin the listeners to it. Without this the balancer takes
    an ephemeral address that changes on recreation, which breaks any DNS record pointing at it.
  EOT
  type        = bool
  default     = true
}

variable "https_port" {
  description = "Port of the TLS listener."
  type        = number
  default     = 443
}

variable "http_port" {
  description = "Port of the plain HTTP listener that redirects to HTTPS."
  type        = number
  default     = 80
}

variable "enable_http_redirect" {
  description = "Add a plain HTTP listener whose only job is a 301 to the HTTPS one."
  type        = bool
  default     = true
}

variable "certificate_id" {
  description = "Existing Certificate Manager certificate for the TLS listener."
  type        = string
  default     = null
}

variable "managed_certificate" {
  description = <<-EOT
    Ask Certificate Manager for a Let's Encrypt certificate instead of supplying one.
    `DNS_CNAME` is the only challenge type that works before the balancer answers traffic,
    which is the usual chicken-and-egg on a first apply.
  EOT

  type = object({
    domains        = list(string)
    challenge_type = optional(string, "DNS_CNAME")
  })

  default = null

  validation {
    condition     = var.managed_certificate == null || contains(["DNS_CNAME", "DNS_TXT", "HTTP"], try(var.managed_certificate.challenge_type, ""))
    error_message = "managed_certificate.challenge_type must be DNS_CNAME, DNS_TXT or HTTP."
  }

  validation {
    condition     = var.managed_certificate == null || length(try(var.managed_certificate.domains, [])) > 0
    error_message = "managed_certificate.domains must list at least one domain."
  }

  validation {
    condition     = !(var.managed_certificate != null && var.certificate_id != null)
    error_message = "Set either certificate_id or managed_certificate, not both."
  }

  validation {
    condition     = var.managed_certificate != null || var.certificate_id != null
    error_message = "A TLS listener needs a certificate: set certificate_id or managed_certificate."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the load balancer."
  type        = list(string)
  default     = []
}

variable "auto_scale_policy" {
  description = <<-EOT
    Capacity in resource units. `min_zone_size` is the floor per zone and is what you pay for
    even at zero traffic; `max_size` caps the total across zones. Null keeps the platform default.
  EOT

  type = object({
    min_zone_size = optional(number, 2)
    max_size      = optional(number)
  })

  default = null

  validation {
    condition = var.auto_scale_policy == null || try(var.auto_scale_policy.max_size, null) == null || try(
      var.auto_scale_policy.max_size >= var.auto_scale_policy.min_zone_size, false
    )
    error_message = "auto_scale_policy.max_size must be at least min_zone_size."
  }
}

variable "log_options" {
  description = "Access logging. `log_group_id` null uses the folder default log group."
  type = object({
    disable      = optional(bool, false)
    log_group_id = optional(string)
  })
  default = {}
}
