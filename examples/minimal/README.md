# examples/minimal

Минимальный работающий стек: одна VPC-сеть, три подсети в разных зонах, общий NAT-шлюз
и две security-группы.

Пример показывает две вещи, которые в реальных конфигурациях путают чаще всего:
подсеть без выхода в интернет (`route_via_nat = false`) и правило security-группы
с диапазоном портов вместо одного порта.

## Что создаётся

| Ресурс | Количество |
|---|---|
| `yandex_vpc_network` | 1 |
| `yandex_vpc_subnet` | 3 (`ru-central1-a`, `ru-central1-b`, `ru-central1-d`) |
| `yandex_vpc_gateway` + `yandex_vpc_route_table` | 1 + 1 |
| `yandex_vpc_security_group` | 2 (базовая и `ssh`) |

Подсеть `private-d` намеренно остаётся без маршрута по умолчанию: хосты в ней видят
только VPC и внутренние эндпоинты Yandex Cloud.

## Запуск

```bash
cp terraform.tfvars.example terraform.tfvars
# заполнить cloud_id и folder_id

export YC_TOKEN="$(yc iam create-token)"
terraform init
terraform plan
terraform apply
```

Удаление:

```bash
terraform destroy
```

## Стоимость

Сеть, подсети, таблица маршрутизации и security-группы в Yandex Cloud бесплатны.
Платным становится только исходящий трафик через NAT-шлюз. То есть этот пример можно
держать поднятым сколько угодно долго, пока через него ничего не ходит.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0, < 2.0.0 |
| yandex | ~> 0.225 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cloud\_id | Yandex Cloud ID. | `string` | n/a | yes |
| folder\_id | Folder everything is created in. | `string` | n/a | yes |
| default\_zone | Zone the provider uses for resources that do not name one explicitly. | `string` | `"ru-central1-a"` | no |
| labels | Labels applied to every resource. | `map(string)` | <pre>{<br/>  "example": "minimal",<br/>  "managed-by": "terraform"<br/>}</pre> | no |
| name\_prefix | Prefix for every resource name. | `string` | `"demo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| default\_security\_group\_id | ID of the baseline security group. |
| nat\_gateway\_id | ID of the shared egress gateway. |
| network\_id | ID of the VPC network. |
| ssh\_security\_group\_id | ID of the SSH security group defined in this example. |
| subnet\_ids | Subnet IDs keyed by subnet suffix. |
<!-- END_TF_DOCS -->