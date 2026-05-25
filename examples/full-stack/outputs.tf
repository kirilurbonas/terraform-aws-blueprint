###############################################################################
# Networking
###############################################################################

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

###############################################################################
# EKS
###############################################################################

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA."
  value       = module.eks.cluster_oidc_issuer_url
}

output "kubeconfig_command" {
  description = "Shell command to update ~/.kube/config."
  value       = replace(module.eks.kubeconfig_command, "<REGION>", var.region)
}

###############################################################################
# RDS
###############################################################################

output "rds_endpoint" {
  description = "RDS endpoint (host:port)."
  value       = module.rds.endpoint
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN for the RDS master credentials."
  value       = module.rds.master_secret_arn
}

###############################################################################
# S3
###############################################################################

output "artifacts_bucket_name" {
  description = "Name of the artifacts bucket."
  value       = module.artifacts_bucket.bucket_id
}

output "artifacts_bucket_arn" {
  description = "ARN of the artifacts bucket."
  value       = module.artifacts_bucket.bucket_arn
}

###############################################################################
# IRSA
###############################################################################

output "app_irsa_role_arn" {
  description = "Role ARN to put in the application's ServiceAccount annotation: eks.amazonaws.com/role-arn."
  value       = module.platform_roles.irsa_role_arn
}
