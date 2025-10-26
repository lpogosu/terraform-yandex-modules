locals {
  zones = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]

  # The control plane and the node groups both need a `zone -> subnet` pair, so the
  # mapping is built once here instead of being repeated in each module call.
  master_locations = [
    for z in local.zones : {
      zone      = z
      subnet_id = module.network.subnet_ids[z]
    }
  ]
}

module "network" {
  source = "../../modules/network"

  name_prefix = var.cluster_name
  folder_id   = var.folder_id
  labels      = var.labels

  subnets = {
    for idx, zone in local.zones : zone => {
      zone           = zone
      v4_cidr_blocks = ["10.20.${idx}.0/24"]
    }
  }

  security_groups = {
    k8s-master = {
      description = "Control plane: API access from inside the VPC"
      ingress = [
        {
          description    = "Kubernetes API"
          protocol       = "TCP"
          port           = 443
          v4_cidr_blocks = ["10.20.0.0/16"]
        },
        {
          description    = "Kubernetes API, alternate port"
          protocol       = "TCP"
          port           = 6443
          v4_cidr_blocks = ["10.20.0.0/16"]
        },
      ]
      egress = [{
        description    = "Control plane to nodes and to the Yandex Cloud API"
        protocol       = "ANY"
        from_port      = 0
        to_port        = 65535
        v4_cidr_blocks = ["0.0.0.0/0"]
      }]
    }
  }
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = var.cluster_name
  folder_id   = var.folder_id

  service_accounts = {
    # The control plane needs to manage load balancers and node instances; it does not
    # need to pull images, which is why the nodes get a separate, much narrower account.
    cluster = {
      description = "Control plane of the ${var.cluster_name} cluster"
      folder_roles = [
        "k8s.clusters.agent",
        "vpc.publicAdmin",
        "load-balancer.admin",
        "logging.writer",
      ]
    }

    nodes = {
      description  = "Nodes of the ${var.cluster_name} cluster"
      folder_roles = ["container-registry.images.puller"]
    }
  }
}

module "kubernetes" {
  source = "../../modules/kubernetes"

  name       = var.cluster_name
  folder_id  = var.folder_id
  network_id = module.network.network_id
  labels     = var.labels

  service_account_id      = module.iam.service_account_ids["cluster"]
  node_service_account_id = module.iam.service_account_ids["nodes"]

  master_type      = "regional"
  master_locations = local.master_locations
  master_version   = var.kubernetes_version
  release_channel  = "STABLE"
  master_public_ip = false

  master_security_group_ids = [
    module.network.default_security_group_id,
    module.network.security_group_ids["k8s-master"],
  ]

  network_policy_provider = "CALICO"

  maintenance_windows = [{
    day        = "sunday"
    start_time = "02:00"
    duration   = "3h"
  }]

  node_groups = {
    # Ingress controllers, monitoring and other cluster add-ons. Fixed size and
    # on-demand instances, because losing these takes the cluster with them.
    system = {
      description = "Cluster add-ons"
      version     = var.kubernetes_version

      locations = [
        for z in local.zones : {
          zone      = z
          subnet_id = module.network.subnet_ids[z]
        }
      ]

      cores     = 2
      memory    = 8
      disk_size = 64

      scale = {
        type = "fixed"
        size = 3
      }

      node_labels = {
        "node-role" = "system"
      }

      node_taints = ["node-role=system:NoSchedule"]

      security_group_ids = [module.network.default_security_group_id]
    }

    # Application workloads. Preemptible: they are ~3x cheaper, the pool autoscales,
    # and everything scheduled here is expected to survive a node disappearing.
    workers = {
      description = "Stateless application workloads"
      version     = var.kubernetes_version

      locations = [
        for z in local.zones : {
          zone      = z
          subnet_id = module.network.subnet_ids[z]
        }
      ]

      cores         = 4
      core_fraction = 100
      memory        = 16
      disk_size     = 128
      preemptible   = true

      scale = {
        type    = "auto"
        min     = var.workers_min
        max     = var.workers_max
        initial = var.workers_min
      }

      node_labels = {
        "node-role"   = "worker"
        "preemptible" = "true"
      }

      security_group_ids = [module.network.default_security_group_id]
    }
  }

  # Folder role bindings are eventually consistent; creating the cluster before the
  # control plane account can actually manage load balancers fails intermittently.
  depends_on = [module.iam]
}
