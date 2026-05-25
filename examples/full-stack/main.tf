terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
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
# Networking — VPC endpoints save NAT egress for ECR pulls and add resilience
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

  enable_s3_gateway_endpoint = true
  interface_endpoints        = ["ecr.api", "ecr.dkr", "sts", "logs", "ec2"]
}

###############################################################################
# Shared KMS key for application-level encryption
###############################################################################

module "app_kms" {
  source = "../../modules/kms"

  environment = var.environment
  project     = var.project
  alias       = "${local.name_prefix}-${var.environment}-app"
  description = "Application-level encryption key (S3, Secrets)"
}

###############################################################################
# EKS — three node groups: system (small ON_DEMAND), apps (mixed SPOT), and a
# managed-add-on baseline so the cluster actually has CNI / DNS / kube-proxy.
###############################################################################

module "eks" {
  source = "../../modules/eks"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access = false

  node_groups = {
    system = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m6i.large"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      labels         = { workload = "system" }
      taints = [
        { key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" },
      ]
    }
    apps = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]
      desired_size   = 3
      min_size       = 3
      max_size       = 12
      labels         = { workload = "apps" }
    }
  }

  cluster_addons = {
    vpc-cni    = {}
    coredns    = {}
    kube-proxy = {}
  }
}

###############################################################################
# RDS — locked down to the EKS node security group, KMS-encrypted, one replica
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
  kms_key_arn     = module.app_kms.key_arn

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  multi_az                 = true
  allocated_storage_gb     = 100
  max_allocated_storage_gb = 500
  backup_retention_days    = 14
  deletion_protection      = true

  read_replicas = {
    ro = { instance_class = "db.m6i.large" }
  }
}

###############################################################################
# Secure S3 bucket for application artifacts, encrypted with the same KMS key
###############################################################################

module "artifacts_bucket" {
  source = "../../modules/s3-secure"

  environment        = var.environment
  project            = var.project
  bucket_name_prefix = "${local.name_prefix}-${var.environment}-artifacts-"

  sse_algorithm = "aws:kms"
  kms_key_arn   = module.app_kms.key_arn

  transition_to_ia_days              = 30
  transition_to_glacier_days         = 180
  expiration_days                    = 730
  noncurrent_version_expiration_days = 90

  tags = { Purpose = "application-artifacts" }
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

  statement {
    sid       = "AppKmsUse"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [module.app_kms.key_arn]
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
