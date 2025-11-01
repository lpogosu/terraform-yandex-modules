# modules/iam

Сервис-аккаунты и привязки ролей одной картой, по принципу наименьших привилегий.

## Что делает

- создаёт сервис-аккаунты из карты `service_accounts`;
- выдаёт роли на каталог и, при необходимости, на облако;
- выпускает статический ключ для Object Storage и авторизованный ключ — только тем
  аккаунтам, которые об этом явно просят.

## Почему так

**`_iam_member`, а не `_iam_binding`.** `yandex_resourcemanager_folder_iam_binding`
авторитетен для всей роли: он молча снесёт грант, выданный другой командой или через
консоль. `_iam_member` управляет одной парой «субъект — роль» и не трогает чужое.
Цена — Terraform не заметит и не уберёт лишний грант, добавленный вручную.

**Роль `admin` запрещена валидацией.** Это не техническое ограничение, а осознанный
барьер: `admin` на каталог перечёркивает смысл разбиения на сервис-аккаунты. Если он
действительно нужен, его выдают вне этого модуля и это видно в ревью.

**Гранты разложены в плоскую карту `"<аккаунт>:<роль>"`.** Адрес в state зависит от имени
аккаунта и роли, а не от позиции в списке, поэтому добавление роли одному аккаунту не
трогает гранты остальных.

**Ключи не создаются по умолчанию.** Статический и авторизованный ключи попадают в state.
Аккаунту, который работает через привязку к ВМ или через Workload Identity, ключ не нужен,
и модуль его не выпустит.

## Пример

```hcl
module "iam" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/iam?ref=v1.0.0"

  name_prefix = "platform"
  folder_id   = var.folder_id

  service_accounts = {
    cluster = {
      folder_roles = ["k8s.clusters.agent", "vpc.publicAdmin", "load-balancer.admin"]
    }
    nodes = {
      folder_roles = ["container-registry.images.puller"]
    }
    ci = {
      folder_roles             = ["container-registry.images.pusher"]
      create_static_access_key = true
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
| [yandex_iam_service_account.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/iam_service_account) | resource |
| [yandex_iam_service_account_key.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/iam_service_account_key) | resource |
| [yandex_iam_service_account_static_access_key.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/iam_service_account_static_access_key) | resource |
| [yandex_resourcemanager_cloud_iam_member.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/resourcemanager_cloud_iam_member) | resource |
| [yandex_resourcemanager_folder_iam_member.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/resourcemanager_folder_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| folder\_id | Folder the service accounts live in and where folder-scoped roles are granted. | `string` | n/a | yes |
| name\_prefix | Prefix prepended to every service account name, so accounts from different stacks do not collide. | `string` | n/a | yes |
| authorized\_key\_algorithm | Key algorithm for generated authorized keys. | `string` | `"RSA_4096"` | no |
| cloud\_id | Cloud ID, required only when a service account requests cloud-scoped roles. | `string` | `null` | no |
| service\_accounts | Service accounts to create, keyed by a short suffix (the account name is `<name_prefix>-<key>`).<br/><br/>`folder_roles` and `cloud_roles` are granted with the non-authoritative `_iam_member`<br/>resources, so a grant made outside Terraform on the same folder is left alone.<br/>Credentials are only materialised when explicitly requested; both are sensitive outputs. | <pre>map(object({<br/>    description              = optional(string, "Managed by Terraform")<br/>    folder_roles             = optional(list(string), [])<br/>    cloud_roles              = optional(list(string), [])<br/>    create_static_access_key = optional(bool, false)<br/>    create_authorized_key    = optional(bool, false)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| authorized\_key\_ids | Authorized key IDs, keyed by service account key. |
| authorized\_private\_keys | PEM private keys of the generated authorized keys, keyed by service account key. |
| granted\_folder\_roles | Folder-scoped role grants that were applied, keyed by `<account>:<role>`. |
| service\_account\_ids | Service account IDs keyed by the key from var.service\_accounts. |
| service\_account\_members | Ready-to-use `serviceAccount:<id>` member strings for further IAM bindings. |
| service\_account\_names | Full service account names keyed by the key from var.service\_accounts. |
| static\_access\_key\_ids | Object Storage access key IDs, keyed by service account key. |
| static\_access\_key\_secrets | Object Storage secret keys, keyed by service account key. Ends up in state - keep the state encrypted. |
<!-- END_TF_DOCS -->
