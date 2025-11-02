# modules/kubernetes

Managed Service for Kubernetes: мастер (региональный или зональный), группы узлов,
описанные картой, и KMS-ключ для шифрования секретов.

## Что делает

- создаёт `yandex_kubernetes_cluster` с мастером в одной зоне или в трёх — переключается
  одной переменной `master_type`;
- создаёт симметричный KMS-ключ и выдаёт сервис-аккаунту мастера роль
  `kms.keys.encrypterDecrypter`, после чего подключает ключ через `kms_provider`;
- создаёт группы узлов из карты `node_groups`: фиксированный размер или автоскейлинг,
  preemptible-флаг, labels, taints, зоны размещения;
- прокидывает окна обслуживания и в мастер, и в группы узлов.

## Почему так

**Группы узлов — карта, а не `count`.** С `count` группа адресуется индексом:
`yandex_kubernetes_node_group.this[1]`. Удаление первой группы сдвигает индексы и приводит
к пересозданию всех остальных — то есть к сливу узлов, которые никто не просил трогать.
С `for_each` по карте адрес — это имя (`this["workers"]`), и рефакторинг соседей ничего
не задевает. Цена — переименование ключа означает пересоздание группы, но это редкая и
хорошо заметная в плане операция.

**KMS-ключ создаётся внутри модуля.** Секреты в etcd шифруются пользовательским ключом,
а не платформенным. Отзыв ключа мгновенно отзывает доступ ко всем секретам кластера.
Ключ по умолчанию защищён от удаления: потеря ключа делает etcd нечитаемым.

**Preemptible требует `auto_repair`.** Платформа останавливает preemptible-узел в течение
суток. Без auto_repair его никто не поднимет, и группа тихо усохнет до нуля. Модуль
не даёт собрать такую конфигурацию.

**`max_unavailable = 0` по умолчанию.** Обновление добавляет узел, а потом дренирует
старый, а не наоборот. Это дороже на один узел на время обновления и заметно спокойнее
для приложений без запаса реплик.

## Пример

```hcl
module "kubernetes" {
  source = "github.com/lpogosu/terraform-yandex-modules//modules/kubernetes?ref=v1.0.0"

  name       = "platform"
  folder_id  = var.folder_id
  network_id = module.network.network_id

  service_account_id      = module.iam.service_account_ids["cluster"]
  node_service_account_id = module.iam.service_account_ids["nodes"]

  master_type = "regional"
  master_locations = [
    { zone = "ru-central1-a", subnet_id = module.network.subnet_ids["ru-central1-a"] },
    { zone = "ru-central1-b", subnet_id = module.network.subnet_ids["ru-central1-b"] },
    { zone = "ru-central1-d", subnet_id = module.network.subnet_ids["ru-central1-d"] },
  ]

  node_groups = {
    workers = {
      locations   = [{ zone = "ru-central1-a", subnet_id = module.network.subnet_ids["ru-central1-a"] }]
      cores       = 4
      memory      = 16
      preemptible = true
      scale       = { type = "auto", min = 2, max = 8 }
    }
  }
}
```

## Права сервис-аккаунтов

Модуль намеренно не создаёт сервис-аккаунты — их даёт `modules/iam`. Минимальный набор:

| Аккаунт | Роли |
|---|---|
| мастер | `k8s.clusters.agent`, `vpc.publicAdmin`, `load-balancer.admin`, `logging.writer` |
| узлы | `container-registry.images.puller` |

Роль `kms.keys.encrypterDecrypter` на созданный ключ модуль выдаёт сам.

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
| [yandex_kms_symmetric_key.secrets](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kms_symmetric_key) | resource |
| [yandex_kms_symmetric_key_iam_member.cluster](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kms_symmetric_key_iam_member) | resource |
| [yandex_kubernetes_cluster.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kubernetes_cluster) | resource |
| [yandex_kubernetes_node_group.this](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kubernetes_node_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| folder\_id | Folder the cluster is created in. | `string` | n/a | yes |
| master\_locations | Where the control plane lives. Exactly one entry for `zonal`, exactly three for `regional`<br/>(Yandex Cloud does not offer any other regional layout). | <pre>list(object({<br/>    zone      = string<br/>    subnet_id = string<br/>  }))</pre> | n/a | yes |
| name | Cluster name. Node groups are named `<name>-<node group key>`. | `string` | n/a | yes |
| network\_id | VPC network the cluster and its nodes live in. | `string` | n/a | yes |
| node\_service\_account\_id | Service account the nodes use (needs container-registry.images.puller at minimum). | `string` | n/a | yes |
| service\_account\_id | Service account the cluster control plane uses (needs k8s.clusters.agent and vpc.publicAdmin). | `string` | n/a | yes |
| cluster\_ipv4\_range | Pod CIDR. Null lets Yandex Cloud pick one; set it explicitly when peering with other networks. | `string` | `null` | no |
| create\_kms\_key | Create a KMS symmetric key and use it to encrypt Kubernetes Secrets at rest. | `bool` | `true` | no |
| description | Cluster description. | `string` | `"Managed by Terraform"` | no |
| kms\_key\_deletion\_protection | Refuse to delete the generated KMS key. Losing it makes every Secret in etcd unreadable,<br/>so this stays true for anything holding real data. | `bool` | `true` | no |
| kms\_key\_id | Existing KMS key to encrypt Secrets with. Ignored when create\_kms\_key is true. | `string` | `null` | no |
| kms\_key\_rotation\_period | Rotation period for the generated KMS key, as a Go duration. | `string` | `"8760h"` | no |
| labels | Labels applied to the cluster and merged into every node group's labels. | `map(string)` | `{}` | no |
| maintenance\_windows | Maintenance windows for the control plane and for node groups that do not override them.<br/>An empty list means "any time", which is what you want for a non-production cluster and<br/>almost never what you want for a production one. | <pre>list(object({<br/>    day        = optional(string)<br/>    start_time = string<br/>    duration   = string<br/>  }))</pre> | `[]` | no |
| master\_auto\_upgrade | Let Yandex Cloud upgrade the control plane inside the maintenance window. | `bool` | `true` | no |
| master\_logging | Ship control plane logs to Cloud Logging. `log_group_id` null sends them to the folder's<br/>default log group. Set `enabled = false` to keep the control plane silent. | <pre>object({<br/>    enabled                    = optional(bool, true)<br/>    log_group_id               = optional(string)<br/>    kube_apiserver_enabled     = optional(bool, true)<br/>    cluster_autoscaler_enabled = optional(bool, true)<br/>    events_enabled             = optional(bool, true)<br/>    audit_enabled              = optional(bool, true)<br/>  })</pre> | `{}` | no |
| master\_public\_ip | Expose the API server on a public address. Keep false and reach the cluster over the VPC where possible. | `bool` | `false` | no |
| master\_security\_group\_ids | Security groups attached to the control plane. | `list(string)` | `[]` | no |
| master\_type | `regional` spreads the control plane over three zones, `zonal` keeps it in one. | `string` | `"regional"` | no |
| master\_version | Kubernetes minor version for the control plane, for example `1.30`. Null lets the release channel decide. | `string` | `null` | no |
| network\_policy\_provider | Network policy engine. `CALICO` enables NetworkPolicy enforcement, null leaves the cluster without it. | `string` | `null` | no |
| node\_groups | Node groups keyed by a short suffix. The key is part of the Terraform address, so renaming a<br/>key replaces the group while editing its body updates it in place.<br/><br/>`scale.type` is `fixed` (uses `size`) or `auto` (uses `min`, `max` and `initial`).<br/>`locations` drives both the allocation policy and the subnets of the node network interface. | <pre>map(object({<br/>    description = optional(string, "Managed by Terraform")<br/>    version     = optional(string)<br/><br/>    locations = list(object({<br/>      zone      = string<br/>      subnet_id = string<br/>    }))<br/><br/>    platform_id        = optional(string, "standard-v3")<br/>    cores              = optional(number, 2)<br/>    core_fraction      = optional(number, 100)<br/>    memory             = optional(number, 8)<br/>    gpus               = optional(number)<br/>    disk_type          = optional(string, "network-ssd")<br/>    disk_size          = optional(number, 64)<br/>    preemptible        = optional(bool, false)<br/>    nat                = optional(bool, false)<br/>    security_group_ids = optional(list(string), [])<br/>    container_runtime  = optional(string, "containerd")<br/>    metadata           = optional(map(string), {})<br/><br/>    scale = object({<br/>      type    = string<br/>      size    = optional(number)<br/>      min     = optional(number)<br/>      max     = optional(number)<br/>      initial = optional(number)<br/>    })<br/><br/>    labels      = optional(map(string), {})<br/>    node_labels = optional(map(string), {})<br/>    node_taints = optional(list(string), [])<br/><br/>    auto_upgrade    = optional(bool, true)<br/>    auto_repair     = optional(bool, true)<br/>    max_expansion   = optional(number, 1)<br/>    max_unavailable = optional(number, 0)<br/>  }))</pre> | `{}` | no |
| node\_ipv4\_cidr\_mask\_size | Size of the pod subnet carved out per node. 24 gives ~110 usable pods, 25 gives ~55. | `number` | `24` | no |
| region | Region used for a regional control plane. | `string` | `"ru-central1"` | no |
| release\_channel | Upgrade channel for the control plane. | `string` | `"STABLE"` | no |
| service\_ipv4\_range | Service CIDR. Null lets Yandex Cloud pick one. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster\_ca\_certificate | PEM CA certificate of the API server, for building a kubeconfig. |
| cluster\_id | ID of the Managed Kubernetes cluster. |
| cluster\_name | Name of the Managed Kubernetes cluster. |
| cluster\_status | Reported cluster status, for example RUNNING. |
| kms\_key\_id | KMS key encrypting Kubernetes Secrets, or null when encryption is disabled. |
| kubeconfig\_command | Yandex Cloud CLI call that writes a kubeconfig entry for this cluster. |
| master\_external\_endpoint | Public API server endpoint, empty when master\_public\_ip is false. |
| master\_internal\_endpoint | In-VPC API server endpoint. |
| master\_version | Kubernetes version the control plane actually runs. |
| node\_group\_ids | Node group IDs keyed by the key from var.node\_groups. |
| node\_group\_instance\_group\_ids | Underlying compute instance group IDs, useful for wiring alerts to node counts. |
<!-- END_TF_DOCS -->
