# modules/alb

Application Load Balancer: целевая группа, backend-группа с health-check'ами, HTTP-роутер
и TLS-listener с сертификатом из Certificate Manager.

## Что делает

- создаёт `yandex_alb_target_group` из списка приватных адресов;
- создаёт `yandex_alb_backend_group` с одним HTTP-бэкендом, health-check'ом и, опционально,
  sticky-сессиями;
- создаёт `yandex_alb_http_router` и виртуальный хост с упорядоченными маршрутами;
- запрашивает управляемый сертификат Let's Encrypt либо принимает готовый;
- резервирует статический публичный адрес и создаёт балансировщик с TLS-listener'ом,
  а при необходимости — с отдельным listener'ом на 80 порту, который редиректит на HTTPS.

## Почему так

**Статический адрес резервируется по умолчанию.** Эфемерный адрес меняется при
пересоздании балансировщика, а DNS-запись на него — нет. Отдельный
`yandex_vpc_address` стоит копейки и снимает целый класс инцидентов.

**Health-check жёстче, чем дефолт.** `unhealthy_threshold = 3` не даёт одному потерянному
пакету выбросить живой бэкенд, а `healthy_threshold = 2` не даёт флапающему бэкенду
вернуться в пул по одному удачному ответу. Валидация отдельно проверяет, что `timeout`
меньше `interval` — иначе проверки накладываются друг на друга.

**Маршруты — список, а не карта.** В ALB порядок маршрутов значим: выигрывает первое
совпадение. Карта в Terraform неупорядочена, поэтому здесь именно список, и `/`
осознанно ставится последним.

**`DNS_CNAME` как тип проверки по умолчанию.** HTTP-проверка требует, чтобы домен уже
вёл на работающий балансировщик, которого на первом `apply` ещё нет. DNS-проверку можно
пройти до создания балансировщика. Записи для неё модуль отдаёт выходом
`certificate_challenges`.

**Пустой список `targets` допустим.** Целевую группу часто наполняет не Terraform, а
ingress-контроллер или группа инстансов. Модуль не мешает такому сценарию.

## Пример

```hcl
module "alb" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/alb?ref=v1.0.0"

  name       = "shop"
  folder_id  = var.folder_id
  network_id = module.network.network_id

  locations = [
    { zone_id = "ru-central1-a", subnet_id = module.network.subnet_ids["ru-central1-a"] },
    { zone_id = "ru-central1-b", subnet_id = module.network.subnet_ids["ru-central1-b"] },
  ]

  targets      = [{ subnet_id = module.network.subnet_ids["ru-central1-a"], ip_address = "10.30.0.11" }]
  backend_port = 8080
  authority    = ["shop.example.com"]

  managed_certificate = {
    domains = ["shop.example.com"]
  }
}
```

После первого `apply` нужно опубликовать записи из `certificate_challenges` — до этого
Certificate Manager сертификат не выпустит, а listener не поднимется.

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
| [yandex_alb_backend_group.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/alb_backend_group) | resource |
| [yandex_alb_http_router.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/alb_http_router) | resource |
| [yandex_alb_load_balancer.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/alb_load_balancer) | resource |
| [yandex_alb_target_group.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/alb_target_group) | resource |
| [yandex_alb_virtual_host.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/alb_virtual_host) | resource |
| [yandex_cm_certificate.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/cm_certificate) | resource |
| [yandex_vpc_address.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_address) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| folder\_id | Folder the load balancer and its components are created in. | `string` | n/a | yes |
| locations | Zones the balancer runs in, with the subnet it uses in each. Two zones is the minimum<br/>that survives losing one; a single zone means the balancer is a single point of failure. | <pre>list(object({<br/>    zone_id         = string<br/>    subnet_id       = string<br/>    disable_traffic = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| name | Base name. The target group, backend group, router and balancer all derive their names from it. | `string` | n/a | yes |
| network\_id | VPC network the load balancer is attached to. | `string` | n/a | yes |
| authority | Host names the virtual host answers to. Empty list matches any Host header. | `list(string)` | `[]` | no |
| auto\_scale\_policy | Capacity in resource units. `min_zone_size` is the floor per zone and is what you pay for<br/>even at zero traffic; `max_size` caps the total across zones. Null keeps the platform default. | <pre>object({<br/>    min_zone_size = optional(number, 2)<br/>    max_size      = optional(number)<br/>  })</pre> | `null` | no |
| backend\_http2 | Speak HTTP/2 to the backends. Only enable it when the backend actually supports h2c. | `bool` | `false` | no |
| backend\_port | Port the backends listen on. | `number` | `80` | no |
| backend\_weight | Relative weight of the backend inside the backend group. | `number` | `100` | no |
| certificate\_id | Existing Certificate Manager certificate for the TLS listener. | `string` | `null` | no |
| enable\_http\_redirect | Add a plain HTTP listener whose only job is a 301 to the HTTPS one. | `bool` | `true` | no |
| healthcheck | HTTP health check for the backend group. `interval` and `timeout` are Go durations with a<br/>unit, for example `1s`. `timeout` must be shorter than `interval`, otherwise checks overlap. | <pre>object({<br/>    path                = optional(string, "/healthz")<br/>    port                = optional(number)<br/>    interval            = optional(string, "2s")<br/>    timeout             = optional(string, "1s")<br/>    healthy_threshold   = optional(number, 2)<br/>    unhealthy_threshold = optional(number, 3)<br/>    expected_statuses   = optional(list(number), [200])<br/>    host                = optional(string)<br/>  })</pre> | `{}` | no |
| http\_port | Port of the plain HTTP listener that redirects to HTTPS. | `number` | `80` | no |
| https\_port | Port of the TLS listener. | `number` | `443` | no |
| internal\_address\_subnet\_id | Subnet holding the internal listener address. Required when `public` is false. | `string` | `null` | no |
| labels | Labels applied to every resource the module creates. | `map(string)` | `{}` | no |
| log\_options | Access logging. `log_group_id` null uses the folder default log group. | <pre>object({<br/>    disable      = optional(bool, false)<br/>    log_group_id = optional(string)<br/>  })</pre> | `{}` | no |
| managed\_certificate | Ask Certificate Manager for a Let's Encrypt certificate instead of supplying one.<br/>`DNS_CNAME` is the only challenge type that works before the balancer answers traffic,<br/>which is the usual chicken-and-egg on a first apply. | <pre>object({<br/>    domains        = list(string)<br/>    challenge_type = optional(string, "DNS_CNAME")<br/>  })</pre> | `null` | no |
| public | Expose the balancer on a public IPv4 address. False builds an internal balancer. | `bool` | `true` | no |
| reserve\_static\_ip | Reserve a static public address and pin the listeners to it. Without this the balancer takes<br/>an ephemeral address that changes on recreation, which breaks any DNS record pointing at it. | `bool` | `true` | no |
| routes | Ordered HTTP routes. The first match wins, so put specific prefixes before `/`.<br/>An empty list installs a single catch-all route to the backend group. | <pre>list(object({<br/>    name           = string<br/>    path_prefix    = optional(string, "/")<br/>    path_exact     = optional(string)<br/>    http_methods   = optional(list(string))<br/>    prefix_rewrite = optional(string)<br/>    timeout        = optional(string, "60s")<br/>    idle_timeout   = optional(string)<br/>    upgrade_types  = optional(list(string))<br/>  }))</pre> | `[]` | no |
| security\_group\_ids | Security groups attached to the load balancer. | `list(string)` | `[]` | no |
| session\_affinity | Sticky sessions: `none`, `connection` (client IP) or `cookie`. | `string` | `"none"` | no |
| session\_affinity\_cookie | Cookie used for sticky sessions. `ttl` is a Go duration; null makes it a session cookie. | <pre>object({<br/>    name = optional(string, "alb-affinity")<br/>    ttl  = optional(string)<br/>  })</pre> | `{}` | no |
| targets | Backend endpoints, addressed by private IP and subnet. Leave empty when the target group is<br/>filled from outside Terraform, for example by a Kubernetes ingress controller. | <pre>list(object({<br/>    subnet_id  = string<br/>    ip_address = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| backend\_group\_id | ID of the backend group. |
| certificate\_challenges | Validation challenges for the managed certificate. Publish the DNS records listed here,<br/>otherwise Certificate Manager never issues the certificate. Empty for a supplied certificate. |
| certificate\_id | Certificate serving the TLS listener. |
| external\_ipv4\_address | Reserved public address of the balancer, or null when it uses an ephemeral or internal address. |
| http\_router\_id | ID of the HTTP router. Attach further virtual hosts to it to serve extra domains. |
| load\_balancer\_id | ID of the application load balancer. |
| load\_balancer\_name | Name of the application load balancer. |
| load\_balancer\_status | Reported balancer status, for example ACTIVE. |
| target\_group\_id | ID of the target group. |
| virtual\_host\_name | Name of the virtual host holding the routes. |
<!-- END_TF_DOCS -->
