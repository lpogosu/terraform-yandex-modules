locals {
  create_service_account = var.service_account_id == null
  service_account_id     = local.create_service_account ? yandex_iam_service_account.this[0].id : var.service_account_id

  create_kms_key = var.enable_server_side_encryption && var.kms_key_id == null
  kms_key_id     = var.enable_server_side_encryption ? (local.create_kms_key ? yandex_kms_symmetric_key.this[0].id : var.kms_key_id) : null

  service_account_name = coalesce(var.service_account_name, "${substr(replace(var.bucket_name, ".", "-"), 0, 55)}-s3")
}

resource "yandex_iam_service_account" "this" {
  count = local.create_service_account ? 1 : 0

  name        = local.service_account_name
  description = "Owns Object Storage bucket ${var.bucket_name}"
  folder_id   = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "storage" {
  for_each = local.create_service_account ? toset(var.service_account_roles) : toset([])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.this[0].id}"
}

# The static key is what the S3 API accepts; the bucket resource below authenticates with it
# instead of the provider-level credentials, so the blast radius of the key is one bucket.
resource "yandex_iam_service_account_static_access_key" "this" {
  service_account_id = local.service_account_id
  description        = "Static access key for bucket ${var.bucket_name}"
}

resource "yandex_kms_symmetric_key" "this" {
  count = local.create_kms_key ? 1 : 0

  name              = "${substr(replace(var.bucket_name, ".", "-"), 0, 50)}-sse"
  description       = "Server-side encryption key for bucket ${var.bucket_name}"
  folder_id         = var.folder_id
  default_algorithm = "AES_256"
  rotation_period   = var.kms_key_rotation_period
  labels            = var.tags
}

# Without this grant the bucket is created and every PutObject then fails with AccessDenied.
resource "yandex_kms_symmetric_key_iam_member" "this" {
  count = var.enable_server_side_encryption ? 1 : 0

  symmetric_key_id = local.kms_key_id
  role             = "kms.keys.encrypterDecrypter"
  member           = "serviceAccount:${local.service_account_id}"
}

resource "yandex_storage_bucket" "this" {
  # checkov:skip=CKV_YC_3: server-side encryption is configured through a dynamic block, which
  # checkov cannot resolve statically. It is enabled unless the caller sets
  # enable_server_side_encryption = false, and the key is created by this module.
  bucket    = var.bucket_name
  folder_id = var.folder_id

  access_key = yandex_iam_service_account_static_access_key.this.access_key
  secret_key = yandex_iam_service_account_static_access_key.this.secret_key

  acl                   = var.acl
  policy                = var.policy
  default_storage_class = var.default_storage_class
  max_size              = var.max_size
  force_destroy         = var.force_destroy
  tags                  = var.tags

  anonymous_access_flags {
    read        = var.anonymous_access_flags.read
    list        = var.anonymous_access_flags.list
    config_read = var.anonymous_access_flags.config_read
  }

  versioning {
    enabled = var.versioning_enabled
  }

  dynamic "server_side_encryption_configuration" {
    for_each = var.enable_server_side_encryption ? [local.kms_key_id] : []

    content {
      rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = server_side_encryption_configuration.value
          sse_algorithm     = "aws:kms"
        }
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules

    content {
      id      = lifecycle_rule.key
      enabled = lifecycle_rule.value.enabled
      prefix  = lifecycle_rule.value.prefix

      abort_incomplete_multipart_upload_days = lifecycle_rule.value.abort_incomplete_multipart_upload_days

      dynamic "expiration" {
        for_each = lifecycle_rule.value.expiration_days != null ? [lifecycle_rule.value.expiration_days] : []

        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lifecycle_rule.value.noncurrent_version_expiration_days != null ? [lifecycle_rule.value.noncurrent_version_expiration_days] : []

        content {
          days = noncurrent_version_expiration.value
        }
      }

      dynamic "transition" {
        for_each = lifecycle_rule.value.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }

  dynamic "logging" {
    for_each = var.logging != null ? [var.logging] : []

    content {
      target_bucket = logging.value.target_bucket
      target_prefix = logging.value.target_prefix
    }
  }

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }

  # IAM grants are eventually consistent: creating the bucket immediately after the
  # binding intermittently fails with AccessDenied without this.
  depends_on = [
    yandex_resourcemanager_folder_iam_member.storage,
    yandex_kms_symmetric_key_iam_member.this,
  ]
}
