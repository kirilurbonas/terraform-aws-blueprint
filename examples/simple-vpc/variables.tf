variable "region" {
  type        = string
  description = "AWS region for the example."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment tag for the example."
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the example VPC."
  default     = "10.10.0.0/16"
}
