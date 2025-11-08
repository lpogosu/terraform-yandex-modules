# modules/postgresql

Кластер Managed Service for PostgreSQL: версия, класс хостов, диск, окно резервного
копирования, пользователи и базы из переменных, по хосту на зону доступности.

## Что делает

- создаёт `yandex_mdb_postgresql_cluster` с хостами из списка `hosts`;
- настраивает окно бэкапа, срок хранения, автоувеличение диска, пулер Odyssey
  и параметры диагностики производительности;
- создаёт пользователей (`yandex_mdb_postgresql_user`) и базы
  (`yandex_mdb_postgresql_database`) отдельными ресурсами;
- умеет поднять кластер восстановлением из бэкапа на точку во времени.

## Про PITR

В Managed Service for PostgreSQL восстановление на точку во времени не включается
отдельным флагом: сервис непрерывно архивирует WAL, а глубина восстановления равна
`backup_retain_period_days`. То есть кластер с retention 14 дней восстанавливается
на любую секунду последних 14 дней. Модуль отражает это буквально: выход
`pitr_window_days` возвращает то же число, а блок `restore` принимает
`backup_id` + `time` для создания кластера на нужный момент.

## Почему так

**Пользователи и базы — отдельные ресурсы, а не вложенные блоки.** Блоки `user {}` и
`database {}` внутри кластера объявлены провайдером устаревшими. Отдельные ресурсы к тому
же дают нормальную гранулярность плана: добавление пользователя не показывает диф по
всему кластеру.

**Пользователи создаются раньше баз.** MDB отказывается создавать базу, владелец которой
ещё не существует, поэтому `owner` ссылается на ресурс пользователя, а не на строку из
переменной — зависимость получается явной.

**Пароль можно не хранить в state.** `generate_password = true` перекладывает генерацию
на Connection Manager, и секрет вообще не проходит через Terraform. Это дефолт для
служебных учёток вроде мониторинга. Пароль приложения обычно нужен снаружи, поэтому для
него остаётся `password` — со всеми последствиями для state.

**Карта `users` не помечена `sensitive`.** Terraform не принимает sensitive-значение в
`for_each`, и обход этого ограничения протащил бы `nonsensitive()` через весь модуль.
Провайдер сам помечает поле `password` чувствительным, так что в выводе плана его не видно.

**PRODUCTION требует минимум двух зон.** Кластер с единственным хостом переживает потерю
зоны ровно так же, как обычная виртуалка. Валидация не даёт назвать такую конфигурацию
продовой по недосмотру.

## Пример

```hcl
module "database" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/postgresql?ref=v1.0.0"

  name       = "shop-pg"
  folder_id  = var.folder_id
  network_id = module.network.network_id

  hosts = [
    { zone = "ru-central1-a", subnet_id = module.network.subnet_ids["ru-central1-a"] },
    { zone = "ru-central1-b", subnet_id = module.network.subnet_ids["ru-central1-b"] },
  ]

  backup_retain_period_days = 14

  users = {
    app = { password = var.db_password, permissions = ["app"] }
  }

  databases = {
    app = { owner = "app", extensions = ["uuid-ossp"] }
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
| [yandex_mdb_postgresql_cluster.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/mdb_postgresql_cluster) | resource |
| [yandex_mdb_postgresql_database.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/mdb_postgresql_database) | resource |
| [yandex_mdb_postgresql_user.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/mdb_postgresql_user) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| folder\_id | Folder the cluster is created in. | `string` | n/a | yes |
| hosts | Cluster hosts. One entry per availability zone gives a highly available cluster;<br/>a single entry gives a cheap single-zone cluster with no automatic failover.<br/>`priority` biases automatic master election (higher wins). | <pre>list(object({<br/>    zone             = string<br/>    subnet_id        = string<br/>    assign_public_ip = optional(bool, false)<br/>    priority         = optional(number)<br/>    name             = optional(string)<br/>  }))</pre> | n/a | yes |
| name | Cluster name. | `string` | n/a | yes |
| network\_id | VPC network the cluster hosts are attached to. | `string` | n/a | yes |
| access | Which Yandex Cloud services may reach the cluster. Everything is off by default. | <pre>object({<br/>    data_lens     = optional(bool, false)<br/>    data_transfer = optional(bool, false)<br/>    serverless    = optional(bool, false)<br/>    web_sql       = optional(bool, false)<br/>  })</pre> | `{}` | no |
| backup\_retain\_period\_days | How long full backups and the WAL archive are kept. This value *is* the point-in-time<br/>recovery window: Managed Service for PostgreSQL keeps continuous WAL for the same period,<br/>so a cluster with 7-day retention can be restored to any second within the last 7 days. | `number` | `7` | no |
| backup\_window\_start | UTC time at which the daily full backup starts. | <pre>object({<br/>    hours   = number<br/>    minutes = optional(number, 0)<br/>  })</pre> | <pre>{<br/>  "hours": 3<br/>}</pre> | no |
| databases | Databases keyed by database name. `owner` must be one of the keys of `var.users`.<br/>`extensions` are installed into the database at creation time. | <pre>map(object({<br/>    owner      = string<br/>    lc_collate = optional(string, "C")<br/>    lc_type    = optional(string, "C")<br/>    extensions = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| deletion\_protection | Refuse to delete the cluster. Keep true for anything holding real data. | `bool` | `true` | no |
| description | Cluster description. | `string` | `"Managed by Terraform"` | no |
| disk\_size | Storage per host in GB. | `number` | `20` | no |
| disk\_size\_autoscaling | Automatic storage growth. `disk_size_limit` is the ceiling in GB; the thresholds are percentages<br/>of current usage. Null disables autoscaling and leaves you with a pager alert instead. | <pre>object({<br/>    disk_size_limit           = number<br/>    planned_usage_threshold   = optional(number, 70)<br/>    emergency_usage_threshold = optional(number, 85)<br/>  })</pre> | `null` | no |
| disk\_type\_id | Storage class. `network-ssd` is the safe default; `local-ssd` and `network-ssd-nonreplicated` need at least three hosts. | `string` | `"network-ssd"` | no |
| environment | `PRODUCTION` gets the conservative maintenance track, `PRESTABLE` gets updates earlier. | `string` | `"PRODUCTION"` | no |
| labels | Labels applied to the cluster. | `map(string)` | `{}` | no |
| maintenance\_window | Maintenance window. `type = ANYTIME` lets Yandex Cloud restart the cluster whenever it likes;<br/>`type = WEEKLY` pins the restart to one weekday and hour. | <pre>object({<br/>    type = optional(string, "ANYTIME")<br/>    day  = optional(string)<br/>    hour = optional(number)<br/>  })</pre> | `{}` | no |
| performance\_diagnostics | Statement and session sampling. Sampling intervals are in seconds. | <pre>object({<br/>    enabled                      = optional(bool, true)<br/>    sessions_sampling_interval   = optional(number, 60)<br/>    statements_sampling_interval = optional(number, 600)<br/>    advanced_mode                = optional(bool, false)<br/>  })</pre> | `{}` | no |
| pooler\_config | Odyssey connection pooler settings. Null keeps the Yandex Cloud defaults (session pooling). | <pre>object({<br/>    pooling_mode = optional(string, "SESSION")<br/>    pool_discard = optional(bool, false)<br/>  })</pre> | `null` | no |
| postgresql\_config | Raw PostgreSQL settings passed straight to the cluster, for example `{ max_connections = "200" }`. | `map(string)` | `{}` | no |
| postgresql\_version | PostgreSQL major version, for example `16`. | `string` | `"16"` | no |
| resource\_preset\_id | Host class, for example `s3-c2-m8` (2 vCPU / 8 GB) or `c3-c4-m16`. | `string` | `"s3-c2-m8"` | no |
| restore | Point-in-time restore. Set `backup_id` and, optionally, `time` (`YYYY-MM-DDTHH:MM:SS` UTC)<br/>to build this cluster from an existing backup instead of an empty database.<br/>Changing it after creation forces a replacement, so leave it null for steady state. | <pre>object({<br/>    backup_id      = string<br/>    time           = optional(string)<br/>    time_inclusive = optional(bool, false)<br/>  })</pre> | `null` | no |
| security\_group\_ids | Security groups attached to the cluster hosts. | `list(string)` | `[]` | no |
| users | Users keyed by user name.<br/><br/>Set `password` for a password you manage yourself, or `generate_password = true` to have<br/>Yandex Cloud create one and keep it in Connection Manager - in that case the secret never<br/>reaches Terraform state. `permissions` lists databases the user may connect to;<br/>`grants` lists roles to hand the user (for example `mdb_monitor`).<br/><br/>The map itself is deliberately not marked `sensitive`: Terraform refuses a sensitive value<br/>in `for_each`, and working around that would push `nonsensitive()` through the whole module.<br/>The provider already marks the user password sensitive, so it stays redacted in plan output. | <pre>map(object({<br/>    password          = optional(string)<br/>    generate_password = optional(bool, false)<br/>    conn_limit        = optional(number, 50)<br/>    login             = optional(bool, true)<br/>    grants            = optional(list(string), [])<br/>    permissions       = optional(list(string), [])<br/>    settings          = optional(map(string), {})<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster\_endpoint | Special FQDN that always resolves to the current master. Use this in application connection strings. |
| cluster\_health | Aggregated cluster health reported by Managed Service for PostgreSQL. |
| cluster\_id | ID of the PostgreSQL cluster. |
| cluster\_name | Name of the PostgreSQL cluster. |
| connection\_uri\_template | Connection URI with placeholders for the credentials, so nothing secret ends up in an output.<br/>Substitute the user and password before use. |
| database\_names | Names of the databases the module created. |
| host\_fqdns | FQDNs of every host, in the order the hosts were declared. |
| hosts\_by\_zone | Host FQDNs grouped by availability zone. |
| pitr\_window\_days | Length of the point-in-time recovery window, which equals the backup retention period. |
| user\_names | Names of the users the module created. |
<!-- END_TF_DOCS -->
