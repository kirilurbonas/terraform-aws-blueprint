terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Example = "terraform-aws-blueprint/web-app"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
  name_prefix = "web"
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project
  }
}

###############################################################################
# Networking — public tier for the ALB, private tier for the service, an
# isolated database tier with no route to the internet
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

  enable_database_subnets       = true
  manage_default_security_group = true

  enable_s3_gateway_endpoint = true
  interface_endpoints        = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
}

###############################################################################
# Encryption key for the database, its secret, logs, and container images
###############################################################################

module "kms" {
  source = "../../modules/kms"

  environment = var.environment
  project     = var.project
  alias       = "${local.name_prefix}-${var.environment}-data"
  description = "web-app data key (Aurora, master secret, ECR)"
}

###############################################################################
# Workload security group — attach it to ECS tasks or EKS pods (security
# groups for pods). The ALB may reach it on the service port; Aurora accepts
# connections only from it.
###############################################################################

resource "aws_security_group" "service" {
  name_prefix = "${local.name_prefix}-${var.environment}-service-"
  description = "web-app service tasks/pods"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${var.environment}-service" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = module.alb.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.service_port
  to_port                      = var.service_port
  description                  = "Service port from the ALB"

  tags = local.common_tags
}

# No 0.0.0.0/0 egress: AWS APIs are reached through the VPC's interface
# endpoints and S3 (where ECR stores image layers) through the gateway
# endpoint's prefix list. Add a rule here if the service must call
# third-party APIs through the NAT gateways.
resource "aws_vpc_security_group_egress_rule" "service_endpoints" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to VPC interface endpoints"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "service_s3" {
  security_group_id = aws_security_group.service.id
  prefix_list_id    = module.vpc.s3_gateway_endpoint_prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to S3 through the gateway endpoint"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "service_postgres" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = module.aurora.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.aurora.port
  to_port                      = module.aurora.port
  description                  = "Postgres to Aurora"

  tags = local.common_tags
}

###############################################################################
# TLS certificate — DNS-validated. Create the records from the
# `certificate_validation_records` output in whichever DNS provider hosts the
# zone; the validation resource waits until ACM issues the certificate.
###############################################################################

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn
}

###############################################################################
# Edge — internet-facing ALB, HTTPS only (TLS 1.3 policy), HTTP redirects
###############################################################################

module "alb" {
  source = "../../modules/alb"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = var.vpc_cidr
  subnet_ids = module.vpc.public_subnet_ids

  certificate_arn = aws_acm_certificate_validation.this.certificate_arn

  # Egress only to the workload, on the service port.
  egress_security_groups = { service = aws_security_group.service.id }
  egress_port_range      = { from_port = var.service_port, to_port = var.service_port }

  target_groups = {
    web = {
      port = var.service_port
      health_check = {
        path = "/healthz"
      }
    }
  }
  default_target_group_key = "web"

  enable_deletion_protection = var.environment == "prod"
}

###############################################################################
# Data — Aurora PostgreSQL Serverless v2, writer + one reader across AZs,
# RDS-managed master secret encrypted with the data key
###############################################################################

module "aurora" {
  source = "../../modules/aurora"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  engine         = "aurora-postgresql"
  engine_version = "16.4"
  instance_class = "db.serverless"
  database_name  = "app"

  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 8
  }

  instances = {
    writer = {}
    reader = { promotion_tier = 1 }
  }

  kms_key_arn = module.kms.key_arn

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids

  allowed_security_groups = { service = aws_security_group.service.id }

  deletion_protection = var.environment == "prod"
}

###############################################################################
# Delivery — immutable, scanned, KMS-encrypted image repository
###############################################################################

module "ecr" {
  source = "../../modules/ecr"

  environment = var.environment
  project     = var.project

  kms_key_arn = module.kms.key_arn

  repositories = {
    "${var.project}/web" = {}
  }
}

###############################################################################
# CI — GitHub Actions assumes a deployer role through OIDC (no stored keys),
# scoped to the main branch and the production environment of one repository.
# It may push images to the one repository and nothing else.
###############################################################################

module "ci" {
  source = "../../modules/iam-roles"

  name_prefix = local.name_prefix
  environment = var.environment
  project     = var.project

  create_ci_deployer_role     = true
  create_github_oidc_provider = var.create_github_oidc_provider

  github_oidc = {
    repositories = [var.github_repository]
    branches     = ["main"]
    environments = [var.environment]
    provider_arn = var.github_oidc_provider_arn
  }

  ci_allowed_statements = [
    {
      sid       = "EcrAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    },
    {
      sid = "EcrPush"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = values(module.ecr.repository_arns)
    },
  ]
}
