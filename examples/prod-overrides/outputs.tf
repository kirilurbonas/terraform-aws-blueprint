output "vpc_id" {
  description = "ID of the VPC backing this example."
  value       = module.vpc.vpc_id
}

output "rds_instance_id" {
  description = "Identifier of the RDS instance that override.tf protects."
  value       = module.rds.db_instance_id
}

output "bucket_id" {
  description = "Name of the S3 bucket that override.tf protects."
  value       = module.bucket.bucket_id
}
