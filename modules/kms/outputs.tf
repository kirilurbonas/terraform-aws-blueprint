output "key_id" {
  description = "KMS key ID."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "KMS key ARN."
  value       = aws_kms_key.this.arn
}

output "alias_arn" {
  description = "ARN of the key alias."
  value       = aws_kms_alias.this.arn
}

output "alias_name" {
  description = "Full alias including the `alias/` prefix."
  value       = aws_kms_alias.this.name
}

output "replica_key_arns" {
  description = "Map of region to replica key ARN. Empty when replica_regions is empty."
  value       = { for region, key in aws_kms_replica_key.this : region => key.arn }
}
