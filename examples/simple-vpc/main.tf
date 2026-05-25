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
      Example = "terraform-aws-blueprint/simple-vpc"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = "demo"
  environment = var.environment
  project     = "blueprint-examples"

  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  # Single NAT to keep the demo cheap.
  nat_gateway_mode = "single"
  enable_flow_logs = false
}
