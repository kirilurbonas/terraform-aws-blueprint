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

###############################################################################
# permissions_boundary_arn
###############################################################################

run "permissions_boundary_applied_to_every_role" {
  command = plan

  variables {
    permissions_boundary_arn  = "arn:aws:iam::111122223333:policy/platform-boundary"
    create_eks_cluster_role   = true
    create_eks_node_role      = true
    create_irsa_role          = true
    irsa_oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_oidc_provider_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_service_account_name = "external-dns"
    create_ci_deployer_role   = true
    ci_trusted_principal_arns = ["arn:aws:iam::444455556666:role/ci"]
  }

  assert {
    condition = alltrue([
      aws_iam_role.eks_cluster[0].permissions_boundary == var.permissions_boundary_arn,
      aws_iam_role.eks_node[0].permissions_boundary == var.permissions_boundary_arn,
      aws_iam_role.irsa[0].permissions_boundary == var.permissions_boundary_arn,
      aws_iam_role.ci_deployer[0].permissions_boundary == var.permissions_boundary_arn,
    ])
    error_message = "every created role should carry the permissions boundary"
  }
}

run "no_permissions_boundary_by_default" {
  command = plan

  variables {
    create_eks_cluster_role = true
  }

  assert {
    condition     = aws_iam_role.eks_cluster[0].permissions_boundary == null
    error_message = "no permissions boundary should be set unless requested"
  }
}

run "rejects_non_policy_permissions_boundary" {
  command         = plan
  expect_failures = [var.permissions_boundary_arn]

  variables {
    permissions_boundary_arn = "arn:aws:iam::111122223333:role/not-a-policy"
  }
}

###############################################################################
# ci_deployer_role — trust paths
###############################################################################

run "ci_cross_account_only_is_unchanged" {
  command = plan

  variables {
    create_ci_deployer_role   = true
    ci_trusted_principal_arns = ["arn:aws:iam::444455556666:role/ci"]
    ci_external_id            = "blueprint"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.ci_assume[0].statement) == 1
    error_message = "without github_oidc the trust policy should hold only the cross-account statement"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "the GitHub OIDC provider should be opt-in"
  }
}

run "ci_github_oidc_with_existing_provider" {
  command = plan

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn  = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories  = ["acme/infra", "acme/app"]
      branches      = ["main"]
      environments  = ["prod"]
      tags          = ["v*"]
      pull_requests = true
    }
  }

  assert {
    condition = toset(local.github_oidc_subjects) == toset([
      "repo:acme/infra:ref:refs/heads/main",
      "repo:acme/infra:ref:refs/tags/v*",
      "repo:acme/infra:environment:prod",
      "repo:acme/infra:pull_request",
      "repo:acme/app:ref:refs/heads/main",
      "repo:acme/app:ref:refs/tags/v*",
      "repo:acme/app:environment:prod",
      "repo:acme/app:pull_request",
    ])
    error_message = "sub patterns should cover every (repository, selector) pair"
  }
  assert {
    condition     = length(data.aws_iam_policy_document.ci_assume[0].statement) == 1
    error_message = "with only github_oidc set, the trust policy should hold only the OIDC statement"
  }
  assert {
    condition     = one(data.aws_iam_policy_document.ci_assume[0].statement[0].actions) == "sts:AssumeRoleWithWebIdentity"
    error_message = "the OIDC statement should use sts:AssumeRoleWithWebIdentity"
  }
  assert {
    condition = one([
      for p in data.aws_iam_policy_document.ci_assume[0].statement[0].principals : p.type == "Federated" && toset(p.identifiers) == toset(["arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"])
    ])
    error_message = "the OIDC statement should federate through the supplied provider"
  }
  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.ci_assume[0].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:aud" && toset(c.values) == toset(["sts.amazonaws.com"])
    ])
    error_message = "the OIDC statement should pin aud to sts.amazonaws.com"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "no provider should be created when provider_arn is supplied"
  }
}

run "ci_github_oidc_creates_provider_alongside_cross_account" {
  command = plan

  variables {
    create_ci_deployer_role     = true
    ci_trusted_principal_arns   = ["arn:aws:iam::444455556666:role/ci"]
    create_github_oidc_provider = true
    ci_max_session_duration     = 7200
    github_oidc = {
      repositories = ["acme/infra"]
      branches     = ["main"]
    }
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "expected a GitHub OIDC provider"
  }
  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "the provider should target the GitHub Actions issuer"
  }
  assert {
    condition     = aws_iam_openid_connect_provider.github[0].client_id_list == toset(["sts.amazonaws.com"])
    error_message = "the provider audience should be sts.amazonaws.com"
  }
  assert {
    condition     = length(data.aws_iam_policy_document.ci_assume[0].statement) == 2
    error_message = "both the cross-account and OIDC trust statements should be present"
  }
  assert {
    condition     = toset(local.github_oidc_subjects) == toset(["repo:acme/infra:ref:refs/heads/main"])
    error_message = "expected a single branch-scoped sub pattern"
  }
  assert {
    condition     = aws_iam_role.ci_deployer[0].max_session_duration == 7200
    error_message = "ci_max_session_duration should be applied"
  }
}

run "rejects_github_oidc_wildcard_owner" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = ["*/infra"]
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_bare_repository" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = ["*"]
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_empty_repositories" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = []
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_without_selector" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = ["acme/infra"]
    }
  }
}

run "rejects_github_oidc_bad_ref" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = ["acme/infra"]
      branches     = ["main:evil"]
    }
  }
}

run "rejects_github_oidc_foreign_provider_arn" {
  command         = plan
  expect_failures = [var.github_oidc]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
      repositories = ["acme/infra"]
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_without_provider" {
  command         = plan
  expect_failures = [data.aws_iam_policy_document.ci_assume]

  variables {
    create_ci_deployer_role = true
    github_oidc = {
      repositories = ["acme/infra"]
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_with_both_providers" {
  command         = plan
  expect_failures = [data.aws_iam_policy_document.ci_assume]

  variables {
    create_ci_deployer_role     = true
    create_github_oidc_provider = true
    github_oidc = {
      provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      repositories = ["acme/infra"]
      branches     = ["main"]
    }
  }
}

run "rejects_github_oidc_provider_without_trust" {
  command         = plan
  expect_failures = [data.aws_iam_policy_document.ci_assume]

  variables {
    create_ci_deployer_role     = true
    ci_trusted_principal_arns   = ["arn:aws:iam::444455556666:role/ci"]
    create_github_oidc_provider = true
  }
}

###############################################################################
# irsa inline policy — plan-time known count
###############################################################################

# The fixture feeds the IRSA role a policy document that references another
# role's ARN, so the JSON is unknown at plan time. Before
# create_irsa_inline_policy existed this failed with "Invalid count argument";
# planning successfully is the assertion.
run "irsa_inline_policy_with_computed_json" {
  command = plan

  module {
    source = "./tests/fixtures/computed_inline_policy"
  }

  variables {
    create_irsa_inline_policy = true
  }
}

run "irsa_inline_policy_not_created_without_json" {
  command = plan

  variables {
    create_irsa_role          = true
    irsa_oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_oidc_provider_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_service_account_name = "app"
  }

  assert {
    condition     = length(aws_iam_role_policy.irsa_inline) == 0
    error_message = "no inline policy should be created without JSON"
  }
}

run "rejects_irsa_inline_flag_without_json" {
  command         = plan
  expect_failures = [aws_iam_role_policy.irsa_inline]

  variables {
    create_irsa_role          = true
    create_irsa_inline_policy = true
    irsa_oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_oidc_provider_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    irsa_service_account_name = "app"
  }
}

run "environment_tag_applied_when_set" {
  command = plan

  variables {
    create_eks_cluster_role = true
    environment             = "prod"
  }

  assert {
    condition     = aws_iam_role.eks_cluster[0].tags["Environment"] == "prod"
    error_message = "environment should be applied as the Environment tag"
  }
}

run "rejects_bad_environment" {
  command         = plan
  expect_failures = [var.environment]

  variables {
    environment = "qa"
  }
}
