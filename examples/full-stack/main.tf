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
      Example = "terraform-aws-blueprint/full-stack"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
  name_prefix = "blueprint"
}

###############################################################################
# Networking
###############################################################################

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs

  nat_gateway_mode = "per_az"
  enable_flow_logs = true
}

###############################################################################
# EKS
###############################################################################

module "eks" {
  source = "../../modules/eks"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  capacity_type    = "ON_DEMAND"
  instance_types   = ["m6i.large", "m6a.large"]
  desired_capacity = 3
  min_capacity     = 3
  max_capacity     = 9

  endpoint_public_access = false
}

###############################################################################
# RDS — locked down to the EKS node security group
###############################################################################

module "rds" {
  source = "../../modules/rds"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.m6i.large"

  db_name         = "appdb"
  master_username = "appadmin"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  multi_az                 = true
  allocated_storage_gb     = 100
  max_allocated_storage_gb = 500
  backup_retention_days    = 14
  deletion_protection      = true
}

###############################################################################
# Secure S3 bucket for application artifacts
###############################################################################

module "artifacts_bucket" {
  source = "../../modules/s3-secure"

  environment        = var.environment
  project            = var.project
  bucket_name_prefix = "${local.name_prefix}-${var.environment}-artifacts-"

  sse_algorithm = "AES256"

  transition_to_ia_days              = 30
  transition_to_glacier_days         = 180
  expiration_days                    = 730
  noncurrent_version_expiration_days = 90

  tags = {
    Purpose = "application-artifacts"
  }
}

###############################################################################
# IRSA role: lets the workload's ServiceAccount read/write the artifacts bucket
###############################################################################

data "aws_iam_policy_document" "app_artifacts_access" {
  statement {
    sid    = "ArtifactReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${module.artifacts_bucket.bucket_arn}/*"]
  }

  statement {
    sid       = "ArtifactList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [module.artifacts_bucket.bucket_arn]
  }
}

module "platform_roles" {
  source = "../../modules/iam-roles"

  name_prefix = local.name_prefix
  project     = var.project

  create_irsa_role          = true
  irsa_oidc_provider_arn    = module.eks.oidc_provider_arn
  irsa_oidc_provider_url    = module.eks.cluster_oidc_issuer_url
  irsa_namespace            = var.app_namespace
  irsa_service_account_name = var.app_service_account
  irsa_inline_policy_json   = data.aws_iam_policy_document.app_artifacts_access.json
}
