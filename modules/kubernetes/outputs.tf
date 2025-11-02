output "cluster_id" {
  description = "ID of the Managed Kubernetes cluster."
  value       = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the Managed Kubernetes cluster."
  value       = yandex_kubernetes_cluster.this.name
}

output "cluster_status" {
  description = "Reported cluster status, for example RUNNING."
  value       = yandex_kubernetes_cluster.this.status
}

output "master_internal_endpoint" {
  description = "In-VPC API server endpoint."
  value       = yandex_kubernetes_cluster.this.master[0].internal_v4_endpoint
}

output "master_external_endpoint" {
  description = "Public API server endpoint, empty when master_public_ip is false."
  value       = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}

output "cluster_ca_certificate" {
  description = "PEM CA certificate of the API server, for building a kubeconfig."
  value       = yandex_kubernetes_cluster.this.master[0].cluster_ca_certificate
  sensitive   = true
}

output "master_version" {
  description = "Kubernetes version the control plane actually runs."
  value       = yandex_kubernetes_cluster.this.master[0].version
}

output "kms_key_id" {
  description = "KMS key encrypting Kubernetes Secrets, or null when encryption is disabled."
  value       = local.kms_key_id
}

output "node_group_ids" {
  description = "Node group IDs keyed by the key from var.node_groups."
  value       = { for k, ng in yandex_kubernetes_node_group.this : k => ng.id }
}

output "node_group_instance_group_ids" {
  description = "Underlying compute instance group IDs, useful for wiring alerts to node counts."
  value       = { for k, ng in yandex_kubernetes_node_group.this : k => ng.instance_group_id }
}

output "kubeconfig_command" {
  description = "Yandex Cloud CLI call that writes a kubeconfig entry for this cluster."
  value       = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.this.id} ${var.master_public_ip ? "--external" : "--internal"} --force"
}
