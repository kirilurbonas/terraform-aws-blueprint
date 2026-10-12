# Test fixture: reproduces an IRSA inline policy whose JSON is only known after
# apply, because it references a resource created in the same run.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

module "source_role" {
  source = "../../.."

  name_prefix             = "fixture-src"
  project                 = "blueprint-tests"
  create_eks_cluster_role = true
}

data "aws_iam_policy_document" "computed" {
  statement {
    actions   = ["iam:GetRole"]
    resources = [module.source_role.eks_cluster_role_arn]
  }
}

module "irsa" {
  source = "../../.."

  name_prefix               = "fixture"
  project                   = "blueprint-tests"
  create_irsa_role          = true
  create_irsa_inline_policy = var.create_irsa_inline_policy
  irsa_oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  irsa_oidc_provider_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  irsa_service_account_name = "app"
  irsa_inline_policy_json   = data.aws_iam_policy_document.computed.json
}
