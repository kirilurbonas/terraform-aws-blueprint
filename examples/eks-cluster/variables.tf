variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment tag."
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.30"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API server to the public internet."
  default     = false
}
