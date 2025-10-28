variable "cloud_id" {
  description = "Yandex Cloud ID."
  type        = string
}

variable "folder_id" {
  description = "Folder everything is created in."
  type        = string
}

variable "default_zone" {
  description = "Zone the provider uses for resources that do not name one explicitly."
  type        = string
  default     = "ru-central1-a"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "demo"
}

variable "labels" {
  description = "Labels applied to every resource."
  type        = map(string)
  default = {
    managed-by = "terraform"
    example    = "minimal"
  }
}
