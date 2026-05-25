mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "test"
  project     = "blueprint-tests"
}

run "no_roles_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.eks_cluster) == 0
    error_message = "eks_cluster_role should be opt-in"
  }
  assert {
    condition     = length(aws_iam_role.eks_node) == 0
    error_message = "eks_node_role should be opt-in"
  }
  assert {
    condition     = length(aws_iam_role.irsa) == 0
    error_message = "irsa_role should be opt-in"
  }
  assert {
    condition     = length(aws_iam_role.ci_deployer) == 0
    error_message = "ci_deployer_role should be opt-in"
  }
}

run "eks_roles_create_correctly" {
  command = plan

  variables {
    create_eks_cluster_role = true
    create_eks_node_role    = true
  }

  assert {
    condition     = length(aws_iam_role.eks_cluster) == 1
    error_message = "expected an eks cluster role"
  }
  assert {
    condition     = length(aws_iam_role.eks_node) == 1
    error_message = "expected an eks node role"
  }
}

run "irsa_with_inline_policy" {
  command = plan

  variables {
    create_irsa_role          = true
    irsa_oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_oidc_provider_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_namespace            = "kube-system"
    irsa_service_account_name = "external-dns"
    irsa_inline_policy_json   = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition     = length(aws_iam_role.irsa) == 1
    error_message = "expected an IRSA role"
  }
}
