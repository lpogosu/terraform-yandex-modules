module "network" {
  source = "../../modules/network"

  name_prefix = var.name_prefix
  folder_id   = var.folder_id
  labels      = var.labels

  subnets = {
    a = {
      zone           = "ru-central1-a"
      v4_cidr_blocks = ["10.10.0.0/24"]
    }
    b = {
      zone           = "ru-central1-b"
      v4_cidr_blocks = ["10.10.1.0/24"]
    }
    # No default route: hosts here reach only the VPC and Yandex Cloud internal endpoints.
    private-d = {
      zone           = "ru-central1-d"
      v4_cidr_blocks = ["10.10.2.0/24"]
      route_via_nat  = false
    }
  }

  security_groups = {
    ssh = {
      description = "SSH from the office range only"
      ingress = [{
        description    = "SSH"
        protocol       = "TCP"
        port           = 22
        v4_cidr_blocks = ["10.0.0.0/8"]
      }]
      egress = [{
        description    = "Everything outbound"
        protocol       = "ANY"
        from_port      = 0
        to_port        = 65535
        v4_cidr_blocks = ["0.0.0.0/0"]
      }]
    }
  }
}
