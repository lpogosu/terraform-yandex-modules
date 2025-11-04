output "network_id" {
  description = "ID of the VPC network."
  value       = yandex_vpc_network.this.id
}

output "network_name" {
  description = "Name of the VPC network."
  value       = yandex_vpc_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by the subnet key from var.subnets."
  value       = { for k, s in yandex_vpc_subnet.this : k => s.id }
}

output "subnet_zones" {
  description = "Availability zone of each subnet, keyed by the subnet key."
  value       = { for k, s in yandex_vpc_subnet.this : k => s.zone }
}

output "subnets_by_zone" {
  description = "Subnet IDs grouped by availability zone. Convenient for spreading hosts across AZs."
  value       = { for s in yandex_vpc_subnet.this : s.zone => s.id... }
}

output "subnet_cidrs" {
  description = "IPv4 CIDR blocks of each subnet, keyed by the subnet key."
  value       = { for k, s in yandex_vpc_subnet.this : k => s.v4_cidr_blocks }
}

output "nat_gateway_id" {
  description = "ID of the shared egress gateway, or null when NAT is disabled."
  value       = local.nat_enabled ? yandex_vpc_gateway.nat[0].id : null
}

output "nat_route_table_id" {
  description = "ID of the route table carrying the default route, or null when NAT is disabled."
  value       = local.nat_enabled ? yandex_vpc_route_table.nat[0].id : null
}

output "default_security_group_id" {
  description = "ID of the baseline security group, or null when it is not created."
  value       = var.create_default_security_group ? yandex_vpc_security_group.default[0].id : null
}

output "security_group_ids" {
  description = "IDs of the additional security groups, keyed by the key from var.security_groups."
  value       = { for k, g in yandex_vpc_security_group.extra : k => g.id }
}
