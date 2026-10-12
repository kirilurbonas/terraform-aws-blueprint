variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev / staging / prod). Also the GitHub environment the CI role trusts."
  default     = "dev"
}

variable "project" {
  type        = string
  description = "Project tag applied to every resource; also the ECR repository namespace."
  default     = "blueprint"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.40.0.0/16"
}

variable "domain_name" {
  type        = string
  description = "Hostname the ALB serves. An ACM certificate is requested for it and validated over DNS."
  default     = "app.example.com"
}

variable "service_port" {
  type        = number
  description = "Port the service listens on inside its tasks/pods."
  default     = 8080
}

variable "github_repository" {
  type        = string
  description = "GitHub repository (owner/repo) whose workflows may assume the CI deployer role."
  default     = "example-org/web-app"
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Create the account's GitHub Actions OIDC provider. Only one may exist per account: set false and pass github_oidc_provider_arn if it already does."
  default     = true
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "Existing token.actions.githubusercontent.com OIDC provider ARN, when create_github_oidc_provider = false."
  default     = null
}
