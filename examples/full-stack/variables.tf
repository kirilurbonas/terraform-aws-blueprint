variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev / staging / prod)."
  default     = "dev"
}

variable "project" {
  type        = string
  description = "Project tag applied to every resource."
  default     = "blueprint"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.30.0.0/16"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.30"
}

variable "app_namespace" {
  type        = string
  description = "Kubernetes namespace of the application service account that gets IRSA bound to the artifacts bucket."
  default     = "app"
}

variable "app_service_account" {
  type        = string
  description = "Kubernetes service account name that gets IRSA bound to the artifacts bucket."
  default     = "app"
}
