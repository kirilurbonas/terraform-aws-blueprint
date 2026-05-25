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
      Example = "terraform-aws-blueprint/prod-overrides"
    }
  }
}

###############################################################################
# This example shows the override.tf pattern used to harden prod stacks
# *without* modifying the upstream module source.
#
# Terraform's `lifecycle.prevent_destroy` must be a literal — it can't read a
# variable. Modules therefore can't toggle it based on `environment`. The
# canonical workaround is to drop a sibling `override.tf` file next to your
# module call, defining the same resource and adding the lifecycle block.
# Terraform merges override files on top of the primary configuration.
#
# Here we wire up RDS + S3 with the blueprint modules; the `override.tf`
# alongside this file pins prevent_destroy on top.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = "prod"
  environment        = "prod"
  project            = "blueprint"
  vpc_cidr           = "10.50.0.0/16"
  availability_zones = local.azs
}

module "rds" {
  source = "../../modules/rds"

  name_prefix    = "prod"
  environment    = "prod"
  project        = "blueprint"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.m6i.large"
  db_name        = "appdb"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = []
  allowed_cidr_blocks        = [module.vpc.vpc_cidr_block]
}

module "bucket" {
  source = "../../modules/s3-secure"

  environment        = "prod"
  project            = "blueprint"
  bucket_name_prefix = "blueprint-prod-data-"
}
