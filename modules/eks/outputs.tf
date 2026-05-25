output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate. Decode and pass to the kubernetes provider."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the cluster control plane ENIs."
  value       = aws_security_group.cluster.id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL used for IRSA trust policies."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider that backs IRSA for this cluster."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_group_arn" {
  description = "ARN of the managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role assumed by worker nodes. Use this in aws-auth role mappings."
  value       = aws_iam_role.node.arn
}

output "node_security_group_id" {
  description = "Security group ID attached to worker nodes."
  value       = aws_security_group.nodes.id
}

output "kms_key_arn" {
  description = "KMS key ARN used for secrets envelope encryption."
  value       = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.eks[0].arn
}

output "kubeconfig_command" {
  description = "Shell command that writes a kubeconfig entry for this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region <REGION> --alias ${aws_eks_cluster.this.name}"
}
