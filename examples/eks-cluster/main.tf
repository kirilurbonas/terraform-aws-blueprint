terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Example = "terraform-aws-blueprint/eks-cluster"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = "eks-demo"
  environment = var.environment
  project     = "blueprint-examples"

  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs

  nat_gateway_mode = "per_az"
  enable_flow_logs = true
}

module "eks" {
  source = "../../modules/eks"

  name_prefix = "eks-demo"
  environment = var.environment
  project     = "blueprint-examples"

  kubernetes_version = var.kubernetes_version

  # Cluster + nodes go into the private subnets carved by the VPC module.
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  capacity_type    = "ON_DEMAND"
  instance_types   = ["t3.large"]
  desired_capacity = 2
  min_capacity     = 1
  max_capacity     = 4

  endpoint_public_access = var.endpoint_public_access
}
