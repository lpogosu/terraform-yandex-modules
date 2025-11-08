# modules/object-storage

Бакет Yandex Object Storage с версионированием, правилами жизненного цикла, серверным
шифрованием, ACL/политикой и собственным сервис-аккаунтом со статическим ключом.

## Что делает

- создаёт сервис-аккаунт, выдаёт ему роли на каталог и выпускает статический ключ доступа;
- создаёт KMS-ключ и выдаёт аккаунту `kms.keys.encrypterDecrypter`, если включено
  серверное шифрование;
- создаёт `yandex_storage_bucket`, аутентифицируясь этим статическим ключом, а не
  учётными данными провайдера;
- настраивает версионирование, правила жизненного цикла, CORS, логирование доступа,
  анонимный доступ и лимит размера.

## Почему так

**У каждого бакета свой сервис-аккаунт.** Модуль не берёт `storage_access_key` из
конфигурации провайдера. Ключ, которым создаётся бакет, принадлежит этому бакету, поэтому
его компрометация не даёт доступа ко всему каталогу. Ценой является один лишний
сервис-аккаунт на бакет.

**Роль по умолчанию `storage.admin`, а не `storage.editor`.** Модуль управляет ACL и
политикой бакета, а это операции уровня admin. Если оставить `acl = "private"` и
`policy = null`, роль стоит понизить до `storage.editor` — переменная это позволяет.

**Правило жизненного цикла обязано что-то делать.** Валидация отклоняет правило без
единого действия: такое правило выглядит рабочим в коде, ничего не удаляет и всплывает
только счётом за хранение.

**Версионирование без истечения неверсионных объектов — ловушка.** Включённое
версионирование само по себе не удаляет ничего никогда. В примерах поэтому всегда есть
`noncurrent_version_expiration_days`.

**Секретный ключ попадает в state.** Иначе бакет создать нечем. Отсюда требование к
бэкенду state: только удалённый и только с шифрованием, см. корневой README.

## Пример

```hcl
module "uploads" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/object-storage?ref=v1.0.0"

  bucket_name = "shop-uploads-b1gyyyyyyyyyyyyyyyyy"
  folder_id   = var.folder_id

  lifecycle_rules = {
    tiering = {
      prefix          = "uploads/"
      expiration_days = 730
      transitions     = [{ days = 30, storage_class = "COLD" }]
    }
    versions = {
      noncurrent_version_expiration_days     = 30
      abort_incomplete_multipart_upload_days = 7
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
| [yandex_iam_service_account_static_access_key.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/iam_service_account_static_access_key) | resource |
| [yandex_kms_symmetric_key.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kms_symmetric_key) | resource |
| [yandex_kms_symmetric_key_iam_member.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kms_symmetric_key_iam_member) | resource |
| [yandex_resourcemanager_folder_iam_member.storage](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/resourcemanager_folder_iam_member) | resource |
| [yandex_storage_bucket.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/storage_bucket) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket\_name | Bucket name. Object Storage names are global, so prefix them with something you own. | `string` | n/a | yes |
| folder\_id | Folder the bucket and its service account belong to. | `string` | n/a | yes |
| acl | Canned ACL applied to the bucket. Anything other than `private` makes bucket contents reachable without credentials. | `string` | `"private"` | no |
| anonymous\_access\_flags | Fine-grained anonymous access. All false keeps the bucket private even if the ACL is loosened. | <pre>object({<br/>    read        = optional(bool, false)<br/>    list        = optional(bool, false)<br/>    config_read = optional(bool, false)<br/>  })</pre> | `{}` | no |
| cors\_rules | CORS rules for browser clients. Empty list means the bucket rejects cross-origin requests. | <pre>list(object({<br/>    allowed_methods = list(string)<br/>    allowed_origins = list(string)<br/>    allowed_headers = optional(list(string))<br/>    expose_headers  = optional(list(string))<br/>    max_age_seconds = optional(number, 3600)<br/>  }))</pre> | `[]` | no |
| default\_storage\_class | Storage class new objects land in. | `string` | `"STANDARD"` | no |
| enable\_server\_side\_encryption | Encrypt every object at rest with a KMS key instead of the platform key. | `bool` | `true` | no |
| force\_destroy | Allow `terraform destroy` to delete a bucket that still holds objects. | `bool` | `false` | no |
| kms\_key\_id | Existing KMS key for server-side encryption. Null makes the module create one. | `string` | `null` | no |
| kms\_key\_rotation\_period | Rotation period for the KMS key the module creates, as a Go duration. | `string` | `"8760h"` | no |
| lifecycle\_rules | Lifecycle rules, keyed by rule id. `prefix` narrows the rule to a key prefix.<br/>`transitions` moves objects to a colder class after N days; `expiration_days` deletes them.<br/>With versioning on, `noncurrent_version_expiration_days` is what actually reclaims space. | <pre>map(object({<br/>    enabled                                = optional(bool, true)<br/>    prefix                                 = optional(string)<br/>    abort_incomplete_multipart_upload_days = optional(number)<br/>    expiration_days                        = optional(number)<br/>    noncurrent_version_expiration_days     = optional(number)<br/>    transitions = optional(list(object({<br/>      days          = number<br/>      storage_class = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| logging | Ship access logs to another bucket. Null disables server access logging. | <pre>object({<br/>    target_bucket = string<br/>    target_prefix = optional(string, "access-logs/")<br/>  })</pre> | `null` | no |
| max\_size | Hard size limit in bytes. Null means unlimited, which also means an unbounded bill. | `number` | `null` | no |
| policy | Bucket policy as a JSON string. Null leaves the bucket without an explicit policy. | `string` | `null` | no |
| service\_account\_id | Existing service account to own the bucket. When null the module creates one, grants it<br/>`service_account_roles` on the folder and issues a static access key for it. | `string` | `null` | no |
| service\_account\_name | Name of the service account created for the bucket. Ignored when service\_account\_id is supplied. | `string` | `null` | no |
| service\_account\_roles | Folder roles granted to the service account the module creates.<br/>`storage.admin` is the default because the module manages the bucket ACL and policy,<br/>which `storage.editor` is not allowed to touch. Drop to `storage.editor` when you<br/>leave both `acl` and `policy` at their defaults. | `list(string)` | <pre>[<br/>  "storage.admin"<br/>]</pre> | no |
| tags | Tags attached to the bucket. | `map(string)` | `{}` | no |
| versioning\_enabled | Keep previous versions of overwritten and deleted objects. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| access\_key\_id | Static access key ID for the bucket service account. |
| bucket\_domain\_name | Virtual-hosted-style domain name of the bucket. |
| bucket\_endpoint | S3 endpoint to point an SDK at. |
| bucket\_name | Name of the bucket. |
| kms\_key\_id | KMS key used for server-side encryption, or null when encryption is left to the platform key. |
| secret\_access\_key | Static secret key for the bucket service account. Stored in Terraform state - keep the state encrypted. |
| service\_account\_id | Service account that owns the bucket. |
| versioning\_enabled | Whether object versioning is on. |
<!-- END_TF_DOCS -->
