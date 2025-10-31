output "service_account_ids" {
  description = "Service account IDs keyed by the key from var.service_accounts."
  value       = { for k, sa in yandex_iam_service_account.this : k => sa.id }
}

output "service_account_names" {
  description = "Full service account names keyed by the key from var.service_accounts."
  value       = { for k, sa in yandex_iam_service_account.this : k => sa.name }
}

output "service_account_members" {
  description = "Ready-to-use `serviceAccount:<id>` member strings for further IAM bindings."
  value       = { for k, sa in yandex_iam_service_account.this : k => "serviceAccount:${sa.id}" }
}

output "granted_folder_roles" {
  description = "Folder-scoped role grants that were applied, keyed by `<account>:<role>`."
  value       = { for k, b in local.folder_bindings : k => b.role }
}

output "static_access_key_ids" {
  description = "Object Storage access key IDs, keyed by service account key."
  value       = { for k, key in yandex_iam_service_account_static_access_key.this : k => key.access_key }
}

output "static_access_key_secrets" {
  description = "Object Storage secret keys, keyed by service account key. Ends up in state - keep the state encrypted."
  value       = { for k, key in yandex_iam_service_account_static_access_key.this : k => key.secret_key }
  sensitive   = true
}

output "authorized_key_ids" {
  description = "Authorized key IDs, keyed by service account key."
  value       = { for k, key in yandex_iam_service_account_key.this : k => key.id }
}

output "authorized_private_keys" {
  description = "PEM private keys of the generated authorized keys, keyed by service account key."
  value       = { for k, key in yandex_iam_service_account_key.this : k => key.private_key }
  sensitive   = true
}
