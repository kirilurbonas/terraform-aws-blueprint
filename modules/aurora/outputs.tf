output "cluster_arn" {
  description = "Aurora cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "cluster_id" {
  description = "Aurora cluster ID (same as the cluster identifier)."
  value       = aws_rds_cluster.this.id
}

output "cluster_identifier" {
  description = "Aurora cluster identifier."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_resource_id" {
  description = "Region-unique, immutable cluster resource ID. Used in IAM database authentication policies (rds-db:connect)."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "cluster_endpoint" {
  description = "Writer endpoint hostname."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Load-balanced reader endpoint hostname."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the cluster is listening on."
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master username."
  value       = aws_rds_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials (username and password)."
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "Security group ID guarding the cluster."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group."
  value       = aws_rds_cluster_parameter_group.this.name
}

output "instance_identifiers" {
  description = "Map of instance key -> cluster instance identifier."
  value       = { for k, i in aws_rds_cluster_instance.this : k => i.identifier }
}

output "instance_endpoints" {
  description = "Map of instance key -> instance endpoint hostname. Prefer cluster_endpoint / reader_endpoint for application traffic."
  value       = { for k, i in aws_rds_cluster_instance.this : k => i.endpoint }
}

output "cloudwatch_log_group_names" {
  description = "Map of exported log type -> CloudWatch log group name."
  value       = { for k, g in aws_cloudwatch_log_group.exports : k => g.name }
}

output "cloudwatch_alarm_arns" {
  description = "Map of alarm key (cpu-utilization, freeable-memory, database-connections, replica-lag) -> CloudWatch alarm ARN. Empty unless create_cloudwatch_alarms = true."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}
