output "cluster_id" {
  description = "ID of the Managed Kubernetes cluster."
  value       = module.kubernetes.cluster_id
}

output "cluster_internal_endpoint" {
  description = "In-VPC API server endpoint."
  value       = module.kubernetes.master_internal_endpoint
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for this cluster."
  value       = module.kubernetes.kubeconfig_command
}

output "node_group_ids" {
  description = "Node group IDs keyed by node group name."
  value       = module.kubernetes.node_group_ids
}

output "secrets_kms_key_id" {
  description = "KMS key encrypting Kubernetes Secrets."
  value       = module.kubernetes.kms_key_id
}

output "service_account_ids" {
  description = "Service accounts created for the cluster."
  value       = module.iam.service_account_ids
}

output "subnet_ids" {
  description = "Subnet IDs keyed by availability zone."
  value       = module.network.subnet_ids
}
