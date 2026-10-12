output "repository_arns" {
  description = "Map of repository name to repository ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_urls" {
  description = "Map of repository name to repository URL (ACCOUNT.dkr.ecr.REGION.amazonaws.com/NAME)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_registry_ids" {
  description = "Map of repository name to the registry ID (account ID) that owns it."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.registry_id }
}

output "registry_id" {
  description = "Registry ID (account ID) of the caller's private registry."
  value       = data.aws_caller_identity.current.account_id
}
