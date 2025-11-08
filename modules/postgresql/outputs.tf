output "cluster_id" {
  description = "ID of the PostgreSQL cluster."
  value       = yandex_mdb_postgresql_cluster.this.id
}

output "cluster_name" {
  description = "Name of the PostgreSQL cluster."
  value       = yandex_mdb_postgresql_cluster.this.name
}

output "cluster_health" {
  description = "Aggregated cluster health reported by Managed Service for PostgreSQL."
  value       = yandex_mdb_postgresql_cluster.this.health
}

output "host_fqdns" {
  description = "FQDNs of every host, in the order the hosts were declared."
  value       = [for h in yandex_mdb_postgresql_cluster.this.host : h.fqdn]
}

output "hosts_by_zone" {
  description = "Host FQDNs grouped by availability zone."
  value       = { for h in yandex_mdb_postgresql_cluster.this.host : h.zone => h.fqdn... }
}

output "cluster_endpoint" {
  description = "Special FQDN that always resolves to the current master. Use this in application connection strings."
  value       = "c-${yandex_mdb_postgresql_cluster.this.id}.rw.mdb.yandexcloud.net"
}

output "database_names" {
  description = "Names of the databases the module created."
  value       = [for db in yandex_mdb_postgresql_database.this : db.name]
}

output "user_names" {
  description = "Names of the users the module created."
  value       = [for u in yandex_mdb_postgresql_user.this : u.name]
}

output "connection_uri_template" {
  description = <<-EOT
    Connection URI with placeholders for the credentials, so nothing secret ends up in an output.
    Substitute the user and password before use.
  EOT
  value       = "postgresql://<user>:<password>@c-${yandex_mdb_postgresql_cluster.this.id}.rw.mdb.yandexcloud.net:6432/<database>?sslmode=verify-full"
}

output "pitr_window_days" {
  description = "Length of the point-in-time recovery window, which equals the backup retention period."
  value       = var.backup_retain_period_days
}
