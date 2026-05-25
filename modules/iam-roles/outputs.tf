output "eks_cluster_role_arn" {
  description = "ARN of the EKS control-plane role, or null if not created."
  value       = try(aws_iam_role.eks_cluster[0].arn, null)
}

output "eks_cluster_role_name" {
  description = "Name of the EKS control-plane role, or null if not created."
  value       = try(aws_iam_role.eks_cluster[0].name, null)
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node-group role, or null if not created."
  value       = try(aws_iam_role.eks_node[0].arn, null)
}

output "eks_node_role_name" {
  description = "Name of the EKS node-group role, or null if not created."
  value       = try(aws_iam_role.eks_node[0].name, null)
}

output "irsa_role_arn" {
  description = "ARN of the IRSA role, or null if not created. Annotate the bound service account with this ARN."
  value       = try(aws_iam_role.irsa[0].arn, null)
}

output "irsa_role_name" {
  description = "Name of the IRSA role, or null if not created."
  value       = try(aws_iam_role.irsa[0].name, null)
}

output "ci_deployer_role_arn" {
  description = "ARN of the CI deployer role, or null if not created."
  value       = try(aws_iam_role.ci_deployer[0].arn, null)
}

output "ci_deployer_role_name" {
  description = "Name of the CI deployer role, or null if not created."
  value       = try(aws_iam_role.ci_deployer[0].name, null)
}
