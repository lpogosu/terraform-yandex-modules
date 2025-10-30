locals {
  certificate_id = var.certificate_id != null ? var.certificate_id : yandex_cm_certificate.this[0].id

  reserve_ip        = var.public && var.reserve_static_ip
  external_address  = local.reserve_ip ? yandex_vpc_address.this[0].external_ipv4_address[0].address : null
  primary_zone      = var.locations[0].zone_id
  healthcheck_ports = var.healthcheck.port != null ? var.healthcheck.port : var.backend_port

  default_route = {
    name           = "default"
    path_prefix    = "/"
    path_exact     = null
    http_methods   = null
    prefix_rewrite = null
    timeout        = "60s"
    idle_timeout   = null
    upgrade_types  = null
  }

  routes = length(var.routes) > 0 ? var.routes : [local.default_route]
}

resource "yandex_cm_certificate" "this" {
  count = var.managed_certificate != null ? 1 : 0

  name        = "${var.name}-cert"
  description = "Managed certificate for ${var.name}"
  folder_id   = var.folder_id
  domains     = var.managed_certificate.domains
  labels      = var.labels

  managed {
    challenge_type = var.managed_certificate.challenge_type
  }
}

# A reserved address survives replacing the balancer, so the DNS record that points at it
# stays valid across a rebuild.
resource "yandex_vpc_address" "this" {
  count = local.reserve_ip ? 1 : 0

  name        = "${var.name}-alb"
  description = "Static address for load balancer ${var.name}"
  folder_id   = var.folder_id
  labels      = var.labels

  external_ipv4_address {
    zone_id = local.primary_zone
  }
}

resource "yandex_alb_target_group" "this" {
  name        = "${var.name}-tg"
  description = "Backends behind ${var.name}"
  folder_id   = var.folder_id
  labels      = var.labels

  dynamic "target" {
    for_each = var.targets

    content {
      subnet_id  = target.value.subnet_id
      ip_address = target.value.ip_address
    }
  }
}

resource "yandex_alb_backend_group" "this" {
  name        = "${var.name}-bg"
  description = "Backend group for ${var.name}"
  folder_id   = var.folder_id
  labels      = var.labels

  http_backend {
    name             = "${var.name}-http"
    port             = var.backend_port
    weight           = var.backend_weight
    http2            = var.backend_http2
    target_group_ids = [yandex_alb_target_group.this.id]

    # An unhealthy_threshold above 1 keeps a single dropped probe from evicting a
    # healthy backend, while healthy_threshold 2 stops a flapping backend from
    # rejoining the pool on one lucky response.
    healthcheck {
      interval            = var.healthcheck.interval
      timeout             = var.healthcheck.timeout
      healthy_threshold   = var.healthcheck.healthy_threshold
      unhealthy_threshold = var.healthcheck.unhealthy_threshold
      healthcheck_port    = local.healthcheck_ports

      http_healthcheck {
        path              = var.healthcheck.path
        host              = var.healthcheck.host
        expected_statuses = var.healthcheck.expected_statuses
        http2             = var.backend_http2
      }
    }
  }

  dynamic "session_affinity" {
    for_each = var.session_affinity == "none" ? [] : [var.session_affinity]

    content {
      dynamic "connection" {
        for_each = session_affinity.value == "connection" ? [1] : []

        content {
          source_ip = true
        }
      }

      dynamic "cookie" {
        for_each = session_affinity.value == "cookie" ? [var.session_affinity_cookie] : []

        content {
          name = cookie.value.name
          ttl  = cookie.value.ttl
        }
      }
    }
  }
}

resource "yandex_alb_http_router" "this" {
  name        = "${var.name}-router"
  description = "HTTP router for ${var.name}"
  folder_id   = var.folder_id
  labels      = var.labels
}

resource "yandex_alb_virtual_host" "this" {
  name           = "${var.name}-vh"
  http_router_id = yandex_alb_http_router.this.id
  authority      = var.authority

  dynamic "route" {
    for_each = local.routes

    content {
      name = route.value.name

      http_route {
        http_match {
          http_method = route.value.http_methods

          path {
            prefix = route.value.path_exact == null ? route.value.path_prefix : null
            exact  = route.value.path_exact
          }
        }

        http_route_action {
          backend_group_id = yandex_alb_backend_group.this.id
          timeout          = route.value.timeout
          idle_timeout     = route.value.idle_timeout
          prefix_rewrite   = route.value.prefix_rewrite
          upgrade_types    = route.value.upgrade_types
        }
      }
    }
  }
}

resource "yandex_alb_load_balancer" "this" {
  name        = var.name
  description = "Application load balancer ${var.name}"
  folder_id   = var.folder_id
  network_id  = var.network_id
  labels      = var.labels

  security_group_ids = var.security_group_ids

  allocation_policy {
    dynamic "location" {
      for_each = var.locations

      content {
        zone_id         = location.value.zone_id
        subnet_id       = location.value.subnet_id
        disable_traffic = location.value.disable_traffic
      }
    }
  }

  dynamic "auto_scale_policy" {
    for_each = var.auto_scale_policy != null ? [var.auto_scale_policy] : []

    content {
      min_zone_size = auto_scale_policy.value.min_zone_size
      max_size      = auto_scale_policy.value.max_size
    }
  }

  listener {
    name = "https"

    endpoint {
      ports = [var.https_port]

      address {
        dynamic "external_ipv4_address" {
          for_each = var.public ? [1] : []

          content {
            address = local.external_address
          }
        }

        dynamic "internal_ipv4_address" {
          for_each = var.public ? [] : [1]

          content {
            subnet_id = var.internal_address_subnet_id
          }
        }
      }
    }

    tls {
      default_handler {
        certificate_ids = [local.certificate_id]

        http_handler {
          http_router_id = yandex_alb_http_router.this.id
        }
      }
    }
  }

  dynamic "listener" {
    for_each = var.enable_http_redirect ? [1] : []

    content {
      name = "http-redirect"

      endpoint {
        ports = [var.http_port]

        address {
          dynamic "external_ipv4_address" {
            for_each = var.public ? [1] : []

            content {
              address = local.external_address
            }
          }

          dynamic "internal_ipv4_address" {
            for_each = var.public ? [] : [1]

            content {
              subnet_id = var.internal_address_subnet_id
            }
          }
        }
      }

      http {
        redirects {
          http_to_https = true
        }
      }
    }
  }

  log_options {
    disable      = var.log_options.disable
    log_group_id = var.log_options.log_group_id
  }
}
