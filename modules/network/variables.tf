variable "name_prefix" {
  description = "Prefix for every resource name created by the module. Also used as the VPC network name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,50}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-52 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "folder_id" {
  description = "Yandex Cloud folder ID the network and its subnets are created in."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "folder_id must be a 20-character Yandex Cloud resource ID."
  }
}

variable "description" {
  description = "Description attached to the VPC network."
  type        = string
  default     = "Managed by Terraform"
}

variable "labels" {
  description = "Labels applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

variable "subnets" {
  description = <<-EOT
    Subnets to create, keyed by a short suffix (the resulting name is `<name_prefix>-<key>`).
    `route_via_nat` attaches the shared egress gateway route table to the subnet;
    set it to false for subnets that must not reach the internet.
  EOT

  type = map(object({
    zone           = string
    v4_cidr_blocks = list(string)
    description    = optional(string, "Managed by Terraform")
    route_via_nat  = optional(bool, true)
  }))

  validation {
    condition     = length(var.subnets) > 0
    error_message = "At least one subnet must be defined."
  }

  validation {
    condition     = alltrue([for s in var.subnets : can(regex("^ru-central1-[a-d]$", s.zone))])
    error_message = "Every subnet zone must be one of ru-central1-a, ru-central1-b, ru-central1-c, ru-central1-d."
  }

  validation {
    condition = alltrue([
      for s in var.subnets : alltrue([
        for c in s.v4_cidr_blocks : can(cidrnetmask(c))
      ])
    ])
    error_message = "Every entry of v4_cidr_blocks must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = alltrue([for s in var.subnets : length(s.v4_cidr_blocks) > 0])
    error_message = "Every subnet must declare at least one IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Create a shared egress NAT gateway and a route table pointing the default route at it."
  type        = bool
  default     = true
}

variable "dhcp_domain_name" {
  description = "Search domain handed out over DHCP inside every subnet. Null leaves the Yandex Cloud default in place."
  type        = string
  default     = null
}

variable "dhcp_domain_name_servers" {
  description = "DNS resolvers handed out over DHCP. Empty list keeps the Yandex Cloud resolver (169.254.2.2)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.dhcp_domain_name_servers : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", ip))])
    error_message = "dhcp_domain_name_servers must contain plain IPv4 addresses."
  }
}

variable "create_default_security_group" {
  description = "Create the baseline security group (intra-group traffic, load balancer health checks, egress)."
  type        = bool
  default     = true
}

variable "default_group_egress_cidr_blocks" {
  description = "Destinations the baseline security group is allowed to reach. Narrow this in regulated environments."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.default_group_egress_cidr_blocks : can(cidrnetmask(c))])
    error_message = "default_group_egress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}

variable "default_group_icmp_sources" {
  description = "Sources allowed to ICMP-ping members of the baseline security group. Empty list disables ICMP."
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition     = alltrue([for c in var.default_group_icmp_sources : can(cidrnetmask(c))])
    error_message = "default_group_icmp_sources must contain valid IPv4 CIDR blocks."
  }
}

variable "security_groups" {
  description = <<-EOT
    Additional security groups, keyed by a short suffix. Rules are expressed with the same
    fields as the provider: use `port` for a single port or `from_port`/`to_port` for a range,
    and exactly one source of `v4_cidr_blocks`, `predefined_target` or `security_group_id`.
  EOT

  type = map(object({
    description = optional(string, "Managed by Terraform")
    ingress = optional(list(object({
      description       = optional(string, "")
      protocol          = string
      port              = optional(number)
      from_port         = optional(number)
      to_port           = optional(number)
      v4_cidr_blocks    = optional(list(string))
      predefined_target = optional(string)
      security_group_id = optional(string)
    })), [])
    egress = optional(list(object({
      description       = optional(string, "")
      protocol          = string
      port              = optional(number)
      from_port         = optional(number)
      to_port           = optional(number)
      v4_cidr_blocks    = optional(list(string))
      predefined_target = optional(string)
      security_group_id = optional(string)
    })), [])
  }))

  default = {}

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) : contains(["ANY", "TCP", "UDP", "ICMP", "IPV6_ICMP", "ESP", "AH"], upper(r.protocol))
      ])
    ])
    error_message = "Rule protocol must be one of ANY, TCP, UDP, ICMP, IPV6_ICMP, ESP, AH."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        length(compact([
          try(length(r.v4_cidr_blocks), 0) > 0 ? "cidr" : "",
          r.predefined_target != null ? "target" : "",
          r.security_group_id != null ? "sg" : "",
        ])) == 1
      ])
    ])
    error_message = "Each rule must set exactly one of v4_cidr_blocks, predefined_target or security_group_id."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        !(r.port != null && (r.from_port != null || r.to_port != null))
      ])
    ])
    error_message = "A rule sets either port or the from_port/to_port pair, never both."
  }
}
