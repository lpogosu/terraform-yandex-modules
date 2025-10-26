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

variable "cluster_name" {
  description = "Cluster name, also used as the prefix for the network and the service accounts."
  type        = string
  default     = "platform"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the control plane and the node groups."
  type        = string
  default     = "1.30"
}

variable "workers_min" {
  description = "Lower bound of the autoscaled worker pool."
  type        = number
  default     = 2
}

variable "workers_max" {
  description = "Upper bound of the autoscaled worker pool."
  type        = number
  default     = 8
}

variable "labels" {
  description = "Labels applied to every resource."
  type        = map(string)
  default = {
    managed-by = "terraform"
    example    = "k8s-cluster"
  }
}
