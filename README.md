# terraform-yandex-modules

Библиотека переиспользуемых Terraform-модулей для Yandex Cloud: сеть, Managed Kubernetes,
Managed PostgreSQL, Object Storage, Application Load Balancer и IAM — с типизированными
входами, валидацией и проверками в CI.

## Задача

Инфраструктура в Yandex Cloud обычно начинается с одного каталога `terraform/`, где лежат
`network.tf`, `k8s.tf`, `db.tf`. Появляется второе окружение — каталог копируется. Появляется
третье — копируется ещё раз. Дальше начинается то, ради чего этот репозиторий и существует:
