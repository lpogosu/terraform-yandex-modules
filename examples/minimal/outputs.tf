output "network_id" {
  description = "ID of the VPC network."
  value       = module.network.network_id
}

output "subnet_ids" {
  description = "Subnet IDs keyed by subnet suffix."
  value       = module.network.subnet_ids
}

output "nat_gateway_id" {
  description = "ID of the shared egress gateway."
  value       = module.network.nat_gateway_id
}

output "default_security_group_id" {
  description = "ID of the baseline security group."
  value       = module.network.default_security_group_id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group defined in this example."
  value       = module.network.security_group_ids["ssh"]
}
