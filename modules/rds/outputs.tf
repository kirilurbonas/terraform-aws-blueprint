output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = aws_db_instance.this.arn
}

output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the RDS instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the database is listening on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master username."
  value       = aws_db_instance.this.username
}

output "master_password" {
  description = "Master password. Prefer reading from Secrets Manager instead of consuming this directly. Null when manage_master_password = true."
  value       = local.master_secret
  sensitive   = true
}

output "master_secret_arn" {
  description = "ARN of the module-managed Secrets Manager secret holding the master credentials JSON. Null when manage_master_password = true; use master_user_secret_arn instead."
  value       = one(aws_secretsmanager_secret.master[*].arn)
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials. Null unless manage_master_password = true."
  value       = var.manage_master_password ? try(aws_db_instance.this.master_user_secret[0].secret_arn, null) : null
}

output "security_group_id" {
  description = "Security group ID guarding the RDS instance."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Name of the parameter group."
  value       = aws_db_parameter_group.this.name
}

output "read_replica_endpoints" {
  description = "Map of replica name -> connection endpoint."
  value       = { for k, r in aws_db_instance.replica : k => r.endpoint }
}

output "read_replica_ids" {
  description = "Map of replica name -> RDS instance identifier."
  value       = { for k, r in aws_db_instance.replica : k => r.id }
}

output "cloudwatch_alarm_arns" {
  description = "Map of alarm key (cpu-utilization, free-storage-space, freeable-memory, database-connections) -> CloudWatch alarm ARN. Empty unless create_cloudwatch_alarms = true."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}
