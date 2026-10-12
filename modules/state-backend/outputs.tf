output "bucket_name" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table. Null when enable_dynamodb_lock = false."
  value       = one(aws_dynamodb_table.lock[*].name)
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table. Null when enable_dynamodb_lock = false."
  value       = one(aws_dynamodb_table.lock[*].arn)
}

output "backend_config_hcl" {
  description = "Ready-to-paste `terraform { backend \"s3\" { ... } }` body for downstream stacks. Uses `dynamodb_table` locking, or `use_lockfile = true` (Terraform >= 1.10) when enable_dynamodb_lock = false."
  value       = var.enable_dynamodb_lock ? local.backend_config_dynamodb : local.backend_config_lockfile
}

output "replication_role_arn" {
  description = "IAM role S3 uses to replicate state — the module-created role, or replication.role_arn when supplied. Null when replication is disabled."
  value       = local.replication_role_arn
}
