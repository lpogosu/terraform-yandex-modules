resource "yandex_mdb_postgresql_cluster" "this" {
  name        = var.name
  description = var.description
  folder_id   = var.folder_id
  network_id  = var.network_id
  environment = var.environment
  labels      = var.labels

  security_group_ids  = var.security_group_ids
  deletion_protection = var.deletion_protection

  config {
    version                   = var.postgresql_version
    backup_retain_period_days = var.backup_retain_period_days
    postgresql_config         = var.postgresql_config

    resources {
      resource_preset_id = var.resource_preset_id
      disk_size          = var.disk_size
      disk_type_id       = var.disk_type_id
    }

    backup_window_start {
      hours   = var.backup_window_start.hours
      minutes = var.backup_window_start.minutes
    }

    access {
      data_lens     = var.access.data_lens
      data_transfer = var.access.data_transfer
      serverless    = var.access.serverless
      web_sql       = var.access.web_sql
    }

    performance_diagnostics {
      enabled                      = var.performance_diagnostics.enabled
      sessions_sampling_interval   = var.performance_diagnostics.sessions_sampling_interval
      statements_sampling_interval = var.performance_diagnostics.statements_sampling_interval
      advanced_mode                = var.performance_diagnostics.advanced_mode
    }

    dynamic "disk_size_autoscaling" {
      for_each = var.disk_size_autoscaling != null ? [var.disk_size_autoscaling] : []

      content {
        disk_size_limit           = disk_size_autoscaling.value.disk_size_limit
        planned_usage_threshold   = disk_size_autoscaling.value.planned_usage_threshold
        emergency_usage_threshold = disk_size_autoscaling.value.emergency_usage_threshold
      }
    }

    dynamic "pooler_config" {
      for_each = var.pooler_config != null ? [var.pooler_config] : []

      content {
        pooling_mode = pooler_config.value.pooling_mode
        pool_discard = pooler_config.value.pool_discard
      }
    }
  }

  dynamic "host" {
    for_each = var.hosts

    content {
      zone             = host.value.zone
      subnet_id        = host.value.subnet_id
      assign_public_ip = host.value.assign_public_ip
      priority         = host.value.priority
      name             = host.value.name
    }
  }

  maintenance_window {
    type = var.maintenance_window.type
    day  = var.maintenance_window.day
    hour = var.maintenance_window.hour
  }

  # Restoring from a backup is a create-time decision; the provider replaces the cluster
  # if this block appears later, which is exactly the wrong thing to do by accident.
  dynamic "restore" {
    for_each = var.restore != null ? [var.restore] : []

    content {
      backup_id      = restore.value.backup_id
      time           = restore.value.time
      time_inclusive = restore.value.time_inclusive
    }
  }
}

# Users come before databases: Managed Service for PostgreSQL refuses to create a
# database whose owner does not exist yet.
resource "yandex_mdb_postgresql_user" "this" {
  for_each = var.users

  cluster_id = yandex_mdb_postgresql_cluster.this.id
  name       = each.key
  conn_limit = each.value.conn_limit
  login      = each.value.login
  grants     = each.value.grants
  settings   = each.value.settings

  password = each.value.password

  # Left null rather than false when a password is supplied: the provider treats the
  # two fields as mutually exclusive and only looks at this flag on creation.
  generate_password = each.value.generate_password ? true : null

  dynamic "permission" {
    for_each = toset(each.value.permissions)

    content {
      database_name = permission.value
    }
  }
}

resource "yandex_mdb_postgresql_database" "this" {
  for_each = var.databases

  cluster_id = yandex_mdb_postgresql_cluster.this.id
  name       = each.key
  owner      = yandex_mdb_postgresql_user.this[each.value.owner].name
  lc_collate = each.value.lc_collate
  lc_type    = each.value.lc_type

  dynamic "extension" {
    for_each = toset(each.value.extensions)

    content {
      name = extension.value
    }
  }
}
