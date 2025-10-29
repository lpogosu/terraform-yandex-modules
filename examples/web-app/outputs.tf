output "load_balancer_address" {
  description = "Public IPv4 address of the balancer. Point the A record for the domain at it."
  value       = module.alb.external_ipv4_address
}

output "certificate_challenges" {
  description = "DNS records that must exist before Certificate Manager issues the certificate."
  value       = module.alb.certificate_challenges
}

output "database_endpoint" {
  description = "FQDN that always resolves to the current PostgreSQL master."
  value       = module.database.cluster_endpoint
}

output "database_hosts" {
  description = "FQDNs of every database host."
  value       = module.database.host_fqdns
}

output "pitr_window_days" {
  description = "How far back the database can be restored."
  value       = module.database.pitr_window_days
}

output "uploads_bucket" {
  description = "Name of the uploads bucket."
  value       = module.uploads.bucket_name
}

output "uploads_access_key_id" {
  description = "Access key ID the application uses to talk to the bucket."
  value       = module.uploads.access_key_id
}

output "uploads_secret_access_key" {
  description = "Secret key for the bucket. Read it with `terraform output -raw uploads_secret_access_key`."
  value       = module.uploads.secret_access_key
  sensitive   = true
}

output "network_id" {
  description = "ID of the VPC network."
  value       = module.network.network_id
}

output "subnet_ids" {
  description = "Subnet IDs keyed by availability zone."
  value       = module.network.subnet_ids
}
