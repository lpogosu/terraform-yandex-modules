locals {
  # Role grants are flattened into "<account key>:<role>" so that adding a role to one
  # account never renumbers the state addresses of the others.
  folder_bindings = merge([
    for sa_key, sa in var.service_accounts : {
      for role in sa.folder_roles : "${sa_key}:${role}" => {
        account = sa_key
        role    = role
      }
    }
  ]...)

  cloud_bindings = merge([
    for sa_key, sa in var.service_accounts : {
      for role in sa.cloud_roles : "${sa_key}:${role}" => {
        account = sa_key
        role    = role
      }
    }
  ]...)

  static_key_accounts    = { for k, sa in var.service_accounts : k => sa if sa.create_static_access_key }
  authorized_key_account = { for k, sa in var.service_accounts : k => sa if sa.create_authorized_key }
}

resource "yandex_iam_service_account" "this" {
  for_each = var.service_accounts

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  folder_id   = var.folder_id
}

# `_iam_member` rather than `_iam_binding`: binding is authoritative for the whole role
# and silently removes grants made by other teams or by the console.
resource "yandex_resourcemanager_folder_iam_member" "this" {
  for_each = local.folder_bindings

  folder_id = var.folder_id
  role      = each.value.role
  member    = "serviceAccount:${yandex_iam_service_account.this[each.value.account].id}"
}

resource "yandex_resourcemanager_cloud_iam_member" "this" {
  for_each = local.cloud_bindings

  cloud_id = var.cloud_id
  role     = each.value.role
  member   = "serviceAccount:${yandex_iam_service_account.this[each.value.account].id}"
}

resource "yandex_iam_service_account_static_access_key" "this" {
  for_each = local.static_key_accounts

  service_account_id = yandex_iam_service_account.this[each.key].id
  description        = "Object Storage static key for ${var.name_prefix}-${each.key}"
}

resource "yandex_iam_service_account_key" "this" {
  for_each = local.authorized_key_account

  service_account_id = yandex_iam_service_account.this[each.key].id
  description        = "Authorized key for ${var.name_prefix}-${each.key}"
  key_algorithm      = var.authorized_key_algorithm
}
