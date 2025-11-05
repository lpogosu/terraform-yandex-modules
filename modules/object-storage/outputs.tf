output "bucket_name" {
  description = "Name of the bucket."
  value       = yandex_storage_bucket.this.bucket
}

output "bucket_domain_name" {
  description = "Virtual-hosted-style domain name of the bucket."
  value       = yandex_storage_bucket.this.bucket_domain_name
}

output "bucket_endpoint" {
  description = "S3 endpoint to point an SDK at."
  value       = "https://storage.yandexcloud.net"
}

output "service_account_id" {
  description = "Service account that owns the bucket."
  value       = local.service_account_id
}

output "access_key_id" {
  description = "Static access key ID for the bucket service account."
  value       = yandex_iam_service_account_static_access_key.this.access_key
}

output "secret_access_key" {
  description = "Static secret key for the bucket service account. Stored in Terraform state - keep the state encrypted."
  value       = yandex_iam_service_account_static_access_key.this.secret_key
  sensitive   = true
}

output "kms_key_id" {
  description = "KMS key used for server-side encryption, or null when encryption is left to the platform key."
  value       = local.kms_key_id
}

output "versioning_enabled" {
  description = "Whether object versioning is on."
  value       = var.versioning_enabled
}
