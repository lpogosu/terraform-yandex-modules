output "load_balancer_id" {
  description = "ID of the application load balancer."
  value       = yandex_alb_load_balancer.this.id
}

output "load_balancer_name" {
  description = "Name of the application load balancer."
  value       = yandex_alb_load_balancer.this.name
}

output "load_balancer_status" {
  description = "Reported balancer status, for example ACTIVE."
  value       = yandex_alb_load_balancer.this.status
}

output "external_ipv4_address" {
  description = "Reserved public address of the balancer, or null when it uses an ephemeral or internal address."
  value       = local.reserve_ip ? yandex_vpc_address.this[0].external_ipv4_address[0].address : null
}

output "target_group_id" {
  description = "ID of the target group."
  value       = yandex_alb_target_group.this.id
}

output "backend_group_id" {
  description = "ID of the backend group."
  value       = yandex_alb_backend_group.this.id
}

output "http_router_id" {
  description = "ID of the HTTP router. Attach further virtual hosts to it to serve extra domains."
  value       = yandex_alb_http_router.this.id
}

output "virtual_host_name" {
  description = "Name of the virtual host holding the routes."
  value       = yandex_alb_virtual_host.this.name
}

output "certificate_id" {
  description = "Certificate serving the TLS listener."
  value       = local.certificate_id
}

output "certificate_challenges" {
  description = <<-EOT
    Validation challenges for the managed certificate. Publish the DNS records listed here,
    otherwise Certificate Manager never issues the certificate. Empty for a supplied certificate.
  EOT
  value       = var.managed_certificate != null ? yandex_cm_certificate.this[0].challenges : []
}
