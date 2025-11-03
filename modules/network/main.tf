locals {
  # A shared egress gateway is only worth creating when at least one subnet
  # actually routes through it; otherwise the route table would dangle unused.
  nat_enabled = var.enable_nat_gateway && length([for s in var.subnets : s if s.route_via_nat]) > 0

  dhcp_enabled = var.dhcp_domain_name != null || length(var.dhcp_domain_name_servers) > 0
}

resource "yandex_vpc_network" "this" {
  name        = var.name_prefix
  description = var.description
  folder_id   = var.folder_id
  labels      = var.labels
}

resource "yandex_vpc_gateway" "nat" {
  count = local.nat_enabled ? 1 : 0

  name        = "${var.name_prefix}-nat"
  description = "Shared egress gateway for ${var.name_prefix}"
  folder_id   = var.folder_id
  labels      = var.labels

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat" {
  count = local.nat_enabled ? 1 : 0

  name        = "${var.name_prefix}-nat"
  description = "Default route via the shared egress gateway"
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.this.id
  labels      = var.labels

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat[0].id
  }
}

resource "yandex_vpc_subnet" "this" {
  for_each = var.subnets

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.this.id
  zone        = each.value.zone
  labels      = var.labels

  v4_cidr_blocks = each.value.v4_cidr_blocks

  # route_table_id is a plain attribute, so the "no NAT" case is expressed as null
  # rather than by omitting a block.
  route_table_id = each.value.route_via_nat && local.nat_enabled ? yandex_vpc_route_table.nat[0].id : null

  dynamic "dhcp_options" {
    for_each = local.dhcp_enabled ? [1] : []

    content {
      domain_name         = var.dhcp_domain_name
      domain_name_servers = length(var.dhcp_domain_name_servers) > 0 ? var.dhcp_domain_name_servers : null
    }
  }
}

# Baseline group. Instances that only need "talk to my peers, answer the balancer,
# reach the internet outbound" attach this and nothing else.
resource "yandex_vpc_security_group" "default" {
  count = var.create_default_security_group ? 1 : 0

  name        = "${var.name_prefix}-default"
  description = "Baseline rules: intra-group traffic, load balancer health checks, egress"
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.this.id
  labels      = var.labels

  # Members reach each other on every port: the port list of an internal service
  # changes far more often than the network topology, and pinning it here turns
  # every application change into a network change.
  ingress {
    description       = "Any traffic between members of this group"
    protocol          = "ANY"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description       = "Yandex Cloud load balancer health checks"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  dynamic "ingress" {
    for_each = toset(var.default_group_icmp_sources)

    content {
      description    = "ICMP from ${ingress.value}"
      protocol       = "ICMP"
      v4_cidr_blocks = [ingress.value]
    }
  }

  # Egress is open by default because package mirrors, container registries and
  # the Yandex Cloud API all live outside the VPC. Override
  # default_group_egress_cidr_blocks where an egress proxy exists.
  egress {
    description    = "Egress to ${join(", ", var.default_group_egress_cidr_blocks)}"
    protocol       = "ANY"
    v4_cidr_blocks = var.default_group_egress_cidr_blocks
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "extra" {
  for_each = var.security_groups

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.this.id
  labels      = var.labels

  dynamic "ingress" {
    for_each = each.value.ingress

    content {
      description       = ingress.value.description
      protocol          = ingress.value.protocol
      port              = ingress.value.port
      from_port         = ingress.value.from_port
      to_port           = ingress.value.to_port
      v4_cidr_blocks    = ingress.value.v4_cidr_blocks
      predefined_target = ingress.value.predefined_target
      security_group_id = ingress.value.security_group_id
    }
  }

  dynamic "egress" {
    for_each = each.value.egress

    content {
      description       = egress.value.description
      protocol          = egress.value.protocol
      port              = egress.value.port
      from_port         = egress.value.from_port
      to_port           = egress.value.to_port
      v4_cidr_blocks    = egress.value.v4_cidr_blocks
      predefined_target = egress.value.predefined_target
      security_group_id = egress.value.security_group_id
    }
  }
}
