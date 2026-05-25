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
  description = "Master password. Prefer reading from Secrets Manager instead of consuming this directly."
  value       = local.master_secret
  sensitive   = true
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials JSON."
  value       = aws_secretsmanager_secret.master.arn
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
