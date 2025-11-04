# modules/network

VPC-сеть, подсети по зонам доступности, общий NAT-шлюз с таблицей маршрутизации и
security-группы с рабочими значениями по умолчанию.

## Что делает

- создаёт `yandex_vpc_network` и по одной `yandex_vpc_subnet` на каждый ключ карты `subnets`;
- поднимает `yandex_vpc_gateway` типа shared egress и таблицу маршрутизации с маршрутом
  `0.0.0.0/0` на него — но только если хотя бы одна подсеть просит `route_via_nat = true`;
- подключает таблицу маршрутизации к тем подсетям, которым она нужна, оставляя остальные
  без выхода в интернет;
- создаёт базовую security-группу: трафик внутри группы, health-check'и балансировщика,
  ICMP из заданных сетей и исходящий трафик;
- создаёт произвольное число дополнительных групп из карты `security_groups`.

## Почему так

**Подсети — карта, а не список.** Ключ карты попадает в адрес ресурса в state
(`yandex_vpc_subnet.this["b"]`). Удаление подсети из середины списка сдвинуло бы индексы и
пересоздало бы все следующие за ней подсети; с картой пересоздаётся ровно одна.

**NAT создаётся только при необходимости.** Шлюз без единой подсети за ним — это
висящий ресурс, который переживёт рефакторинг и будет годами непонятно зачем стоять
в аккаунте.

**Базовая группа разрешает весь трафик внутри себя.** Набор портов внутреннего сервиса
меняется чаще, чем топология сети. Если зафиксировать порты здесь, каждый релиз
приложения превращается в правку сетевой конфигурации.

## Пример

```hcl
module "network" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/network?ref=v1.0.0"

  name_prefix = "prod"
  folder_id   = var.folder_id

  subnets = {
    a = { zone = "ru-central1-a", v4_cidr_blocks = ["10.10.0.0/24"] }
    b = { zone = "ru-central1-b", v4_cidr_blocks = ["10.10.1.0/24"] }
    db = {
      zone           = "ru-central1-d"
      v4_cidr_blocks = ["10.10.2.0/24"]
      route_via_nat  = false
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0, < 2.0.0 |
| yandex | ~> 0.225 |

## Providers

| Name | Version |
|------|---------|
| yandex | ~> 0.225 |

## Resources

| Name | Type |
|------|------|
| [yandex_vpc_gateway.nat](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_gateway) | resource |
| [yandex_vpc_network.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_network) | resource |
| [yandex_vpc_route_table.nat](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_route_table) | resource |
| [yandex_vpc_security_group.default](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_security_group) | resource |
| [yandex_vpc_security_group.extra](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_security_group) | resource |
| [yandex_vpc_subnet.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_subnet) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| folder\_id | Yandex Cloud folder ID the network and its subnets are created in. | `string` | n/a | yes |
| name\_prefix | Prefix for every resource name created by the module. Also used as the VPC network name. | `string` | n/a | yes |
| subnets | Subnets to create, keyed by a short suffix (the resulting name is `<name_prefix>-<key>`).<br/>`route_via_nat` attaches the shared egress gateway route table to the subnet;<br/>set it to false for subnets that must not reach the internet. | <pre>map(object({<br/>    zone           = string<br/>    v4_cidr_blocks = list(string)<br/>    description    = optional(string, "Managed by Terraform")<br/>    route_via_nat  = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| create\_default\_security\_group | Create the baseline security group (intra-group traffic, load balancer health checks, egress). | `bool` | `true` | no |
| default\_group\_egress\_cidr\_blocks | Destinations the baseline security group is allowed to reach. Narrow this in regulated environments. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| default\_group\_icmp\_sources | Sources allowed to ICMP-ping members of the baseline security group. Empty list disables ICMP. | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| description | Description attached to the VPC network. | `string` | `"Managed by Terraform"` | no |
| dhcp\_domain\_name | Search domain handed out over DHCP inside every subnet. Null leaves the Yandex Cloud default in place. | `string` | `null` | no |
| dhcp\_domain\_name\_servers | DNS resolvers handed out over DHCP. Empty list keeps the Yandex Cloud resolver (169.254.2.2). | `list(string)` | `[]` | no |
| enable\_nat\_gateway | Create a shared egress NAT gateway and a route table pointing the default route at it. | `bool` | `true` | no |
| labels | Labels applied to every resource the module creates. | `map(string)` | `{}` | no |
| security\_groups | Additional security groups, keyed by a short suffix. Rules are expressed with the same<br/>fields as the provider: use `port` for a single port or `from_port`/`to_port` for a range,<br/>and exactly one source of `v4_cidr_blocks`, `predefined_target` or `security_group_id`. | <pre>map(object({<br/>    description = optional(string, "Managed by Terraform")<br/>    ingress = optional(list(object({<br/>      description       = optional(string, "")<br/>      protocol          = string<br/>      port              = optional(number)<br/>      from_port         = optional(number)<br/>      to_port           = optional(number)<br/>      v4_cidr_blocks    = optional(list(string))<br/>      predefined_target = optional(string)<br/>      security_group_id = optional(string)<br/>    })), [])<br/>    egress = optional(list(object({<br/>      description       = optional(string, "")<br/>      protocol          = string<br/>      port              = optional(number)<br/>      from_port         = optional(number)<br/>      to_port           = optional(number)<br/>      v4_cidr_blocks    = optional(list(string))<br/>      predefined_target = optional(string)<br/>      security_group_id = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| default\_security\_group\_id | ID of the baseline security group, or null when it is not created. |
| nat\_gateway\_id | ID of the shared egress gateway, or null when NAT is disabled. |
| nat\_route\_table\_id | ID of the route table carrying the default route, or null when NAT is disabled. |
| network\_id | ID of the VPC network. |
| network\_name | Name of the VPC network. |
| security\_group\_ids | IDs of the additional security groups, keyed by the key from var.security\_groups. |
| subnet\_cidrs | IPv4 CIDR blocks of each subnet, keyed by the subnet key. |
| subnet\_ids | Subnet IDs keyed by the subnet key from var.subnets. |
| subnet\_zones | Availability zone of each subnet, keyed by the subnet key. |
| subnets\_by\_zone | Subnet IDs grouped by availability zone. Convenient for spreading hosts across AZs. |
<!-- END_TF_DOCS -->
