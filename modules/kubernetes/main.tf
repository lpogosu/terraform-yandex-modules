locals {
  kms_key_id = var.create_kms_key ? yandex_kms_symmetric_key.secrets[0].id : var.kms_key_id
}

# Secrets in etcd are encrypted with a customer key rather than a platform key, so
# revoking the key revokes access to every Secret in the cluster at once.
resource "yandex_kms_symmetric_key" "secrets" {
  count = var.create_kms_key ? 1 : 0

  name                = "${var.name}-k8s-secrets"
  description         = "Envelope key for Kubernetes Secrets of cluster ${var.name}"
  folder_id           = var.folder_id
  default_algorithm   = "AES_256"
  rotation_period     = var.kms_key_rotation_period
  deletion_protection = var.kms_key_deletion_protection
  labels              = var.labels
}

# The control plane service account has to be able to use the key; without this the
# cluster comes up and then fails every Secret read.
resource "yandex_kms_symmetric_key_iam_member" "cluster" {
  count = var.create_kms_key ? 1 : 0

  symmetric_key_id = yandex_kms_symmetric_key.secrets[0].id
  role             = "kms.keys.encrypterDecrypter"
  member           = "serviceAccount:${var.service_account_id}"
}

resource "yandex_kubernetes_cluster" "this" {
  name        = var.name
  description = var.description
  folder_id   = var.folder_id
  network_id  = var.network_id
  labels      = var.labels

  service_account_id      = var.service_account_id
  node_service_account_id = var.node_service_account_id

  release_channel          = var.release_channel
  network_policy_provider  = var.network_policy_provider
  cluster_ipv4_range       = var.cluster_ipv4_range
  service_ipv4_range       = var.service_ipv4_range
  node_ipv4_cidr_mask_size = var.node_ipv4_cidr_mask_size

  master {
    version            = var.master_version
    public_ip          = var.master_public_ip
    security_group_ids = var.master_security_group_ids

    dynamic "zonal" {
      for_each = var.master_type == "zonal" ? [var.master_locations[0]] : []

      content {
        zone      = zonal.value.zone
        subnet_id = zonal.value.subnet_id
      }
    }

    dynamic "regional" {
      for_each = var.master_type == "regional" ? [1] : []

      content {
        region = var.region

        dynamic "location" {
          for_each = var.master_locations

          content {
            zone      = location.value.zone
            subnet_id = location.value.subnet_id
          }
        }
      }
    }

    maintenance_policy {
      auto_upgrade = var.master_auto_upgrade

      dynamic "maintenance_window" {
        for_each = var.maintenance_windows

        content {
          day        = maintenance_window.value.day
          start_time = maintenance_window.value.start_time
          duration   = maintenance_window.value.duration
        }
      }
    }

    dynamic "master_logging" {
      for_each = var.master_logging.enabled ? [var.master_logging] : []

      content {
        enabled                    = true
        log_group_id               = master_logging.value.log_group_id
        kube_apiserver_enabled     = master_logging.value.kube_apiserver_enabled
        cluster_autoscaler_enabled = master_logging.value.cluster_autoscaler_enabled
        events_enabled             = master_logging.value.events_enabled
        audit_enabled              = master_logging.value.audit_enabled
      }
    }
  }

  dynamic "kms_provider" {
    for_each = local.kms_key_id != null ? [local.kms_key_id] : []

    content {
      key_id = kms_provider.value
    }
  }

  depends_on = [yandex_kms_symmetric_key_iam_member.cluster]
}

resource "yandex_kubernetes_node_group" "this" {
  for_each = var.node_groups

  cluster_id  = yandex_kubernetes_cluster.this.id
  name        = "${var.name}-${each.key}"
  description = each.value.description
  version     = each.value.version

  labels      = merge(var.labels, each.value.labels)
  node_labels = each.value.node_labels
  node_taints = each.value.node_taints

  instance_template {
    platform_id = each.value.platform_id
    metadata    = each.value.metadata

    container_runtime {
      type = each.value.container_runtime
    }

    network_interface {
      subnet_ids         = distinct([for l in each.value.locations : l.subnet_id])
      nat                = each.value.nat
      security_group_ids = each.value.security_group_ids
    }

    resources {
      cores         = each.value.cores
      core_fraction = each.value.core_fraction
      memory        = each.value.memory
      gpus          = each.value.gpus
    }

    boot_disk {
      type = each.value.disk_type
      size = each.value.disk_size
    }

    scheduling_policy {
      preemptible = each.value.preemptible
    }
  }

  scale_policy {
    dynamic "fixed_scale" {
      for_each = each.value.scale.type == "fixed" ? [each.value.scale] : []

      content {
        size = fixed_scale.value.size
      }
    }

    dynamic "auto_scale" {
      for_each = each.value.scale.type == "auto" ? [each.value.scale] : []

      content {
        min     = auto_scale.value.min
        max     = auto_scale.value.max
        initial = coalesce(auto_scale.value.initial, auto_scale.value.min)
      }
    }
  }

  allocation_policy {
    dynamic "location" {
      for_each = each.value.locations

      content {
        zone      = location.value.zone
        subnet_id = location.value.subnet_id
      }
    }
  }

  maintenance_policy {
    auto_upgrade = each.value.auto_upgrade
    auto_repair  = each.value.auto_repair

    dynamic "maintenance_window" {
      for_each = var.maintenance_windows

      content {
        day        = maintenance_window.value.day
        start_time = maintenance_window.value.start_time
        duration   = maintenance_window.value.duration
      }
    }
  }

  # max_unavailable defaults to 0 so a rolling upgrade adds a node before draining one.
  # Autoscaled groups that sit at their maximum need max_expansion room to make progress.
  deploy_policy {
    max_expansion   = each.value.max_expansion
    max_unavailable = each.value.max_unavailable
  }
}
