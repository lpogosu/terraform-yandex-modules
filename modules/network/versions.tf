terraform {
  # 1.9 is the floor because several modules in this library use cross-variable
  # references inside `validation` blocks, which older releases reject at parse time.
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.225"
    }
  }
}
