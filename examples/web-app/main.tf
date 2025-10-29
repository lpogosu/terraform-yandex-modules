locals {
  zones = ["ru-central1-a", "ru-central1-b"]

  subnet_cidrs = {
    "ru-central1-a" = "10.30.0.0/24"
    "ru-central1-b" = "10.30.1.0/24"
  }

  alb_locations = [
    for z in local.zones : {
      zone_id   = z
      subnet_id = module.network.subnet_ids[z]
    }
  ]

  alb_targets = [
    for t in var.app_backend_ips : {
      subnet_id  = module.network.subnet_ids[t.zone]
      ip_address = t.ip_address
    }
  ]
}

module "network" {
  source = "../../modules/network"

  name_prefix = var.app_name
  folder_id   = var.folder_id
  labels      = var.labels

  subnets = {
    for z in local.zones : z => {
      zone           = z
      v4_cidr_blocks = [local.subnet_cidrs[z]]
    }
  }

  security_groups = {
    # The balancer is the only thing allowed in from the internet.
    alb = {
      description = "Public entry point"
      ingress = [
        {
          description    = "HTTPS from anywhere"
          protocol       = "TCP"
          port           = 443
          v4_cidr_blocks = ["0.0.0.0/0"]
        },
        {
          description    = "HTTP from anywhere, redirected to HTTPS by the balancer"
          protocol       = "TCP"
          port           = 80
          v4_cidr_blocks = ["0.0.0.0/0"]
        },
        {
          description       = "Health checks from the load balancer service"
          protocol          = "TCP"
          from_port         = 0
          to_port           = 65535
          predefined_target = "loadbalancer_healthchecks"
        },
      ]
      egress = [{
        description    = "Balancer to the application subnets"
        protocol       = "ANY"
        from_port      = 0
        to_port        = 65535
        v4_cidr_blocks = values(local.subnet_cidrs)
      }]
    }

    # PostgreSQL is reachable from the application subnets and from nowhere else.
    database = {
      description = "Managed PostgreSQL hosts"
      ingress = [{
        description    = "PostgreSQL and the Odyssey pooler"
        protocol       = "TCP"
        from_port      = 6432
        to_port        = 6432
        v4_cidr_blocks = values(local.subnet_cidrs)
      }]
      egress = [{
        description    = "Replication and backups inside the VPC"
        protocol       = "ANY"
        from_port      = 0
        to_port        = 65535
        v4_cidr_blocks = values(local.subnet_cidrs)
      }]
    }
  }
}

module "database" {
  source = "../../modules/postgresql"

  name       = "${var.app_name}-pg"
  folder_id  = var.folder_id
  network_id = module.network.network_id
  labels     = var.labels

  environment        = "PRODUCTION"
  postgresql_version = "16"
  resource_preset_id = "s3-c2-m8"
  disk_size          = var.db_disk_size
  disk_type_id       = "network-ssd"

  hosts = [
    for z in local.zones : {
      zone      = z
      subnet_id = module.network.subnet_ids[z]
    }
  ]

  security_group_ids = [module.network.security_group_ids["database"]]

  backup_window_start = {
    hours   = 2
    minutes = 30
  }

  # Two weeks of retention is also two weeks of point-in-time recovery.
  backup_retain_period_days = 14

  disk_size_autoscaling = {
    disk_size_limit = var.db_disk_size * 4
  }

  maintenance_window = {
    type = "WEEKLY"
    day  = "SUN"
    hour = 3
  }

  # Transaction pooling: the application opens far more connections than the
  # cluster can serve directly, and it does not rely on session state.
  pooler_config = {
    pooling_mode = "TRANSACTION"
  }

  # Only settings that are plain scalars go here; anything enum-shaped in the MDB API
  # is easier to get wrong than to get right, and belongs in a reviewed change of its own.
  postgresql_config = {
    max_connections            = "200"
    log_min_duration_statement = "500"
  }

  users = {
    app = {
      password    = var.db_password
      conn_limit  = 150
      permissions = ["app"]
    }

    # Read-only account for dashboards and ad-hoc queries. The password lives in
    # Connection Manager and never reaches Terraform state.
    reporting = {
      generate_password = true
      conn_limit        = 20
      grants            = ["mdb_monitor"]
      permissions       = ["app"]
    }
  }

  databases = {
    app = {
      owner      = "app"
      lc_collate = "C"
      lc_type    = "C"
      extensions = ["uuid-ossp", "pg_trgm"]
    }
  }
}

module "uploads" {
  source = "../../modules/object-storage"

  bucket_name = var.bucket_name
  folder_id   = var.folder_id
  tags        = var.labels

  acl                = "private"
  versioning_enabled = true

  lifecycle_rules = {
    # Uploads are hot for a month, then cheap to keep and rarely read.
    archive-old-uploads = {
      prefix          = "uploads/"
      expiration_days = 730
      transitions = [{
        days          = 30
        storage_class = "COLD"
      }]
    }

    # Versioning without expiry grows without bound.
    expire-old-versions = {
      noncurrent_version_expiration_days     = 30
      abort_incomplete_multipart_upload_days = 7
    }
  }

  cors_rules = [{
    allowed_methods = ["GET"]
    allowed_origins = ["https://${var.domain_name}"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }]
}

module "alb" {
  source = "../../modules/alb"

  name       = var.app_name
  folder_id  = var.folder_id
  network_id = module.network.network_id
  labels     = var.labels

  locations = local.alb_locations
  targets   = local.alb_targets

  security_group_ids = [module.network.security_group_ids["alb"]]

  backend_port   = var.app_port
  backend_weight = 100

  healthcheck = {
    path                = "/healthz"
    interval            = "2s"
    timeout             = "1s"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  authority = [var.domain_name]

  routes = [
    {
      name        = "static"
      path_prefix = "/static/"
      timeout     = "10s"
    },
    {
      name          = "websocket"
      path_prefix   = "/ws"
      timeout       = "3600s"
      idle_timeout  = "300s"
      upgrade_types = ["websocket"]
    },
    {
      name        = "app"
      path_prefix = "/"
      timeout     = "30s"
    },
  ]

  managed_certificate = {
    domains        = [var.domain_name]
    challenge_type = "DNS_CNAME"
  }

  auto_scale_policy = {
    min_zone_size = 2
    max_size      = 10
  }
}
