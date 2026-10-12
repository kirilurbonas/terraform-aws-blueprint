terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      ManagedBy = "Terraform"
      Project   = var.project
      Module    = "terraform-aws-blueprint/iam-roles"
    },
    var.environment == null ? {} : { Environment = var.environment },
    var.tags,
  )

  name_prefix = var.name_prefix

  # GitHub Actions OIDC trust for the CI deployer role. The provider ARN is
  # either supplied by the caller or comes from the provider this module creates
  # (an account holds at most one provider per issuer URL, so creation is opt-in).
  github_oidc_enabled = var.create_ci_deployer_role && var.github_oidc != null

  github_oidc_provider_arn = (
    !local.github_oidc_enabled ? null :
    var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn :
    var.github_oidc.provider_arn
  )

  # One `sub` pattern per (repository, selector) pair. GitHub formats the claim
  # as repo:<owner>/<repo>:<context>, where context is ref:refs/heads/<branch>,
  # ref:refs/tags/<tag>, environment:<name>, or pull_request.
  github_oidc_subjects = !local.github_oidc_enabled ? [] : distinct(flatten([
    for repo in var.github_oidc.repositories : concat(
      [for b in var.github_oidc.branches : "repo:${repo}:ref:refs/heads/${b}"],
      [for t in var.github_oidc.tags : "repo:${repo}:ref:refs/tags/${t}"],
      [for e in var.github_oidc.environments : "repo:${repo}:environment:${e}"],
      var.github_oidc.pull_requests ? ["repo:${repo}:pull_request"] : [],
    )
  ]))
}

###############################################################################
# eks_cluster_role
###############################################################################

data "aws_iam_policy_document" "eks_cluster_assume" {
  count = var.create_eks_cluster_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count = var.create_eks_cluster_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-eks-cluster-"
  assume_role_policy   = data.aws_iam_policy_document.eks_cluster_assume[0].json
  description          = "EKS control plane service role"
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
    Role = "eks-cluster"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.create_eks_cluster_role ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# eks_node_role
###############################################################################

data "aws_iam_policy_document" "eks_node_assume" {
  count = var.create_eks_node_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  count = var.create_eks_node_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-eks-node-"
  assume_role_policy   = data.aws_iam_policy_document.eks_node_assume[0].json
  description          = "EKS managed-node-group instance role"
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-role"
    Role = "eks-node"
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

###############################################################################
# irsa_role  (IAM Role for Service Account)
#
# Binds <namespace>/<service_account_name> in the target cluster to an IAM role
# via the cluster's OIDC provider.
###############################################################################

data "aws_iam_policy_document" "irsa_assume" {
  count = var.create_irsa_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.irsa_oidc_provider_arn]
    }

    # Scope the trust to one specific ServiceAccount in one namespace.
    condition {
      test     = "StringEquals"
      variable = "${replace(var.irsa_oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.irsa_namespace}:${var.irsa_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.irsa_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  count = var.create_irsa_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-irsa-${var.irsa_service_account_name}-"
  assume_role_policy   = data.aws_iam_policy_document.irsa_assume[0].json
  description          = "IRSA role for ${var.irsa_namespace}/${var.irsa_service_account_name}"
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.common_tags, {
    Name              = "${local.name_prefix}-irsa-${var.irsa_service_account_name}"
    Role              = "irsa"
    K8sNamespace      = var.irsa_namespace
    K8sServiceAccount = var.irsa_service_account_name
  })
}

resource "aws_iam_role_policy_attachment" "irsa_managed" {
  for_each = var.create_irsa_role ? toset(var.irsa_managed_policy_arns) : toset([])

  role       = aws_iam_role.irsa[0].name
  policy_arn = each.value
}

# `count` must be known at plan time. A policy JSON computed in the same apply
# (e.g. a policy document referencing a bucket created alongside) is unknown,
# so create_irsa_inline_policy lets the caller assert its presence statically;
# `true || <unknown>` evaluates to true.
resource "aws_iam_role_policy" "irsa_inline" {
  count = var.create_irsa_role && (var.create_irsa_inline_policy || var.irsa_inline_policy_json != null) ? 1 : 0

  name   = "inline"
  role   = aws_iam_role.irsa[0].id
  policy = var.irsa_inline_policy_json

  lifecycle {
    precondition {
      condition     = var.irsa_inline_policy_json != null
      error_message = "create_irsa_inline_policy = true requires irsa_inline_policy_json."
    }
  }
}

###############################################################################
# ci_deployer_role
#
# Assumable role used by external CI/CD systems. Two trust paths, usable
# together: cross-account IAM principals (optionally with sts:ExternalId), and
# GitHub Actions OIDC federation scoped to specific repositories and refs.
# Permissions are limited to caller-supplied (actions, resources) pairs.
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_ci_deployer_role && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list omitted: IAM validates this issuer against its own trusted
  # CA store and ignores configured thumbprints.

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-actions-oidc"
  })
}

data "aws_iam_policy_document" "ci_assume" {
  count = var.create_ci_deployer_role ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.github_oidc == null || (try(var.github_oidc.provider_arn, null) != null) != var.create_github_oidc_provider
      error_message = "github_oidc requires exactly one of github_oidc.provider_arn or create_github_oidc_provider = true."
    }
    precondition {
      condition     = !var.create_github_oidc_provider || var.github_oidc != null
      error_message = "create_github_oidc_provider = true requires github_oidc to be set."
    }
  }

  # Cross-account principal path. Always rendered when GitHub OIDC is not in
  # use, so existing configurations produce an unchanged trust policy.
  dynamic "statement" {
    for_each = length(var.ci_trusted_principal_arns) > 0 || !local.github_oidc_enabled ? [1] : []
    content {
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = var.ci_trusted_principal_arns
      }

      dynamic "condition" {
        for_each = var.ci_external_id != null ? [1] : []
        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = [var.ci_external_id]
        }
      }

      dynamic "condition" {
        for_each = length(var.ci_source_ip_cidrs) > 0 ? [1] : []
        content {
          test     = "IpAddress"
          variable = "aws:SourceIp"
          values   = var.ci_source_ip_cidrs
        }
      }
    }
  }

  # GitHub Actions OIDC path.
  dynamic "statement" {
    for_each = local.github_oidc_enabled ? [1] : []
    content {
      sid     = "GitHubActionsOIDC"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [local.github_oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      }

      # StringLike so callers can pass patterns such as `release/*`; the
      # repository owner is always literal (enforced in variables.tf).
      condition {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = local.github_oidc_subjects
      }

      # Self-hosted runners only: GitHub-hosted runner egress IPs are not stable.
      dynamic "condition" {
        for_each = length(var.ci_source_ip_cidrs) > 0 ? [1] : []
        content {
          test     = "IpAddress"
          variable = "aws:SourceIp"
          values   = var.ci_source_ip_cidrs
        }
      }
    }
  }
}

data "aws_iam_policy_document" "ci_permissions" {
  count = var.create_ci_deployer_role ? 1 : 0

  dynamic "statement" {
    for_each = var.ci_allowed_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "ci_deployer" {
  count = var.create_ci_deployer_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-ci-deployer-"
  assume_role_policy   = data.aws_iam_policy_document.ci_assume[0].json
  max_session_duration = var.ci_max_session_duration
  description          = "Cross-account CI/CD deployer role"
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ci-deployer-role"
    Role = "ci-deployer"
  })
}

resource "aws_iam_role_policy" "ci_deployer" {
  count = var.create_ci_deployer_role ? 1 : 0

  name   = "permissions"
  role   = aws_iam_role.ci_deployer[0].id
  policy = data.aws_iam_policy_document.ci_permissions[0].json
}
