mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  environment = "dev"
  project     = "blueprint-tests"
  repositories = {
    app = {}
  }
}

###############################################################################
# Defaults
###############################################################################

run "defaults_are_hardened" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this["app"].image_tag_mutability == "IMMUTABLE"
    error_message = "repositories should default to IMMUTABLE tags"
  }

  assert {
    condition     = aws_ecr_repository.this["app"].image_scanning_configuration[0].scan_on_push == true
    error_message = "repositories should scan on push by default"
  }

  assert {
    # kms_key is optional + computed, so leaving it null (AWS managed key) is
    # unknown at plan time and cannot be asserted here.
    condition     = aws_ecr_repository.this["app"].encryption_configuration[0].encryption_type == "KMS"
    error_message = "repositories should default to KMS encryption"
  }

  assert {
    condition     = aws_ecr_repository.this["app"].force_delete == false
    error_message = "force_delete should default to false"
  }

  assert {
    condition     = aws_ecr_repository.this["app"].tags["Module"] == "terraform-aws-blueprint/ecr" && aws_ecr_repository.this["app"].tags["Name"] == "app"
    error_message = "repositories should carry the common tags and a Name tag"
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "no repository policy should be created without principals or lambda_pull"
  }

  assert {
    condition = (
      length(aws_ecr_registry_scanning_configuration.this) == 0 &&
      length(aws_ecr_pull_through_cache_rule.this) == 0 &&
      length(aws_ecr_replication_configuration.this) == 0
    )
    error_message = "registry-level resources must be off by default"
  }

  assert {
    condition     = output.registry_id == "111122223333"
    error_message = "registry_id should be the caller's account ID"
  }
}

run "empty_repositories_plan_cleanly" {
  command = plan

  variables {
    repositories = {}
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 0 && output.repository_arns == {}
    error_message = "an empty repositories map should create nothing"
  }
}

###############################################################################
# Fan-out and per-repository settings
###############################################################################

run "multiple_repositories_fan_out" {
  command = plan

  variables {
    encryption_type = "AES256"
    repositories = {
      "team/api" = {}
      worker = {
        image_tag_mutability = "MUTABLE"
        scan_on_push         = false
        force_delete         = true
      }
      "base.images_x-1" = {}
    }
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 3 && length(aws_ecr_lifecycle_policy.this) == 3
    error_message = "expected one repository and one lifecycle policy per map entry"
  }

  assert {
    condition     = aws_ecr_repository.this["team/api"].name == "team/api"
    error_message = "repository name should be the map key"
  }

  assert {
    condition = (
      aws_ecr_repository.this["worker"].image_tag_mutability == "MUTABLE" &&
      aws_ecr_repository.this["worker"].image_scanning_configuration[0].scan_on_push == false &&
      aws_ecr_repository.this["worker"].force_delete == true
    )
    error_message = "per-repository overrides should be applied"
  }

  assert {
    condition     = aws_ecr_repository.this["worker"].encryption_configuration[0].encryption_type == "AES256"
    error_message = "encryption_type should apply to every repository"
  }

  assert {
    condition     = toset(keys(output.repository_urls)) == toset(["team/api", "worker", "base.images_x-1"])
    error_message = "repository_urls should be keyed by repository name"
  }
}

run "customer_managed_kms_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/EXAMPLE"
  }

  assert {
    condition     = aws_ecr_repository.this["app"].encryption_configuration[0].kms_key == "arn:aws:kms:us-east-1:111122223333:key/EXAMPLE"
    error_message = "kms_key_arn should be wired into the repository encryption configuration"
  }
}

###############################################################################
# Lifecycle policy
###############################################################################

run "lifecycle_policy_default_shape" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules) == 3
    error_message = "default lifecycle policy should have untagged, tagged and any rules"
  }

  assert {
    condition     = [for r in jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules : r.rulePriority] == [1, 2, 3]
    error_message = "rule priorities should be 1..n in list order"
  }

  assert {
    condition     = [for r in jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules : r.selection.tagStatus] == ["untagged", "tagged", "any"]
    error_message = "rules should be ordered untagged, tagged, any"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[0].selection.countType == "sinceImagePushed" &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[0].selection.countUnit == "days" &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[0].selection.countNumber == 14
    )
    error_message = "untagged images should expire 14 days after push by default"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[1].selection.tagPrefixList == ["v", "release"] &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[1].selection.countType == "imageCountMoreThan" &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[1].selection.countNumber == 30
    )
    error_message = "tagged rule should keep the last 30 images tagged v* / release*"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[2].selection.countNumber == 100 &&
      !can(jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[2].selection.tagPrefixList)
    )
    error_message = "the any rule should keep 100 images and carry no tag prefix list"
  }

  assert {
    condition     = alltrue([for r in jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules : r.action.type == "expire"])
    error_message = "every rule should expire images"
  }
}

run "lifecycle_policy_overrides" {
  command = plan

  variables {
    lifecycle_keep_any_count = null
    repositories = {
      app = {
        untagged_expire_days = 3
        keep_tagged_count    = 5
        tagged_prefixes      = ["prod-"]
      }
      no-tagged = {
        tagged_prefixes = []
        keep_any_count  = 20
      }
      minimal = {
        tagged_prefixes = []
      }
    }
  }

  assert {
    condition = (
      length(jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules) == 2 &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[0].selection.countNumber == 3 &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[1].selection.countNumber == 5 &&
      jsondecode(aws_ecr_lifecycle_policy.this["app"].policy).rules[1].selection.tagPrefixList == ["prod-"]
    )
    error_message = "per-repository lifecycle overrides should replace module defaults, and a null keep_any_count drops the any rule"
  }

  assert {
    condition = (
      [for r in jsondecode(aws_ecr_lifecycle_policy.this["no-tagged"].policy).rules : r.selection.tagStatus] == ["untagged", "any"] &&
      [for r in jsondecode(aws_ecr_lifecycle_policy.this["no-tagged"].policy).rules : r.rulePriority] == [1, 2] &&
      jsondecode(aws_ecr_lifecycle_policy.this["no-tagged"].policy).rules[1].selection.countNumber == 20
    )
    error_message = "an empty tagged_prefixes list should drop the tagged rule and keep the any rule last"
  }

  assert {
    condition     = [for r in jsondecode(aws_ecr_lifecycle_policy.this["minimal"].policy).rules : r.selection.tagStatus] == ["untagged"]
    error_message = "with no tagged prefixes and no any count only the untagged rule should remain"
  }
}

###############################################################################
# Repository policy
###############################################################################

run "cross_account_policy_rendered_only_with_principals" {
  command = plan

  variables {
    repositories = {
      shared = {
        pull_principals = ["444455556666", "arn:aws:iam::777788889999:role/deployer"]
        push_principals = ["arn:aws:iam::444455556666:role/ci"]
      }
      private = {}
    }
  }

  assert {
    condition     = keys(aws_ecr_repository_policy.this) == ["shared"]
    error_message = "a repository policy should exist only for repositories with principals"
  }

  assert {
    condition = (
      data.aws_iam_policy_document.repository["shared"].statement[0].sid == "CrossAccountPull" &&
      toset(data.aws_iam_policy_document.repository["shared"].statement[0].actions) == toset(["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"])
    )
    error_message = "pull statement should grant exactly the three pull actions"
  }

  assert {
    condition = (
      toset(flatten([for p in data.aws_iam_policy_document.repository["shared"].statement[0].principals : p.identifiers])) ==
      toset(["arn:aws:iam::444455556666:root", "arn:aws:iam::777788889999:role/deployer"])
    )
    error_message = "account IDs should be expanded to root ARNs and IAM ARNs passed through"
  }

  assert {
    condition = (
      data.aws_iam_policy_document.repository["shared"].statement[1].sid == "CrossAccountPush" &&
      contains(data.aws_iam_policy_document.repository["shared"].statement[1].actions, "ecr:PutImage") &&
      contains(flatten([for p in data.aws_iam_policy_document.repository["shared"].statement[1].principals : p.identifiers]), "arn:aws:iam::444455556666:role/ci")
    )
    error_message = "push statement should grant PutImage to the push principals"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.repository["shared"].statement) == 2
    error_message = "no lambda statement should be rendered unless lambda_pull = true"
  }
}

run "lambda_pull_statement" {
  command = plan

  variables {
    repositories = {
      fn = {
        lambda_pull     = true
        pull_principals = ["arn:aws:iam::444455556666:root"]
      }
    }
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1
    error_message = "lambda_pull should create a repository policy"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.repository["fn"].statement :
      s.sid == "LambdaPull" &&
      contains(flatten([for p in s.principals : p.identifiers]), "lambda.amazonaws.com") &&
      toset(flatten([for c in s.condition : c.values if c.variable == "aws:sourceArn"])) == toset([
        "arn:aws:lambda:us-east-1:111122223333:function:*",
        "arn:aws:lambda:us-east-1:444455556666:function:*",
      ])
    ])
    error_message = "lambda statement should be scoped by aws:sourceArn to this account and the pull principals' accounts"
  }
}

###############################################################################
# Registry-level resources
###############################################################################

run "registry_scanning_enabled" {
  command = plan

  variables {
    registry_scanning = {
      scan_type = "ENHANCED"
      rules = [
        { scan_frequency = "CONTINUOUS_SCAN", filter = "prod/*" },
        { scan_frequency = "SCAN_ON_PUSH" },
      ]
    }
  }

  assert {
    condition     = aws_ecr_registry_scanning_configuration.this[0].scan_type == "ENHANCED" && length(aws_ecr_registry_scanning_configuration.this[0].rule) == 2
    error_message = "registry scanning should render the scan type and one rule per entry"
  }

  assert {
    condition = toset(flatten([
      for r in aws_ecr_registry_scanning_configuration.this[0].rule : [for f in r.repository_filter : "${r.scan_frequency}=${f.filter}/${f.filter_type}"]
    ])) == toset(["CONTINUOUS_SCAN=prod/*/WILDCARD", "SCAN_ON_PUSH=*/WILDCARD"])
    error_message = "scan rules should use WILDCARD filters, defaulting to *"
  }
}

run "pull_through_cache_rules_enabled" {
  command = plan

  variables {
    pull_through_cache_rules = {
      ecr-public = {
        upstream_registry_url = "public.ecr.aws"
      }
      docker-hub = {
        upstream_registry_url = "registry-1.docker.io"
        credential_arn        = "arn:aws:secretsmanager:us-east-1:111122223333:secret:ecr-pullthroughcache/docker-hub-AbCdEf"
      }
    }
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.this) == 2
    error_message = "expected one pull-through cache rule per map entry"
  }

  assert {
    condition = (
      aws_ecr_pull_through_cache_rule.this["docker-hub"].ecr_repository_prefix == "docker-hub" &&
      aws_ecr_pull_through_cache_rule.this["docker-hub"].credential_arn == "arn:aws:secretsmanager:us-east-1:111122223333:secret:ecr-pullthroughcache/docker-hub-AbCdEf" &&
      aws_ecr_pull_through_cache_rule.this["ecr-public"].credential_arn == null
    )
    error_message = "pull-through cache rules should use the map key as prefix and pass credential_arn through"
  }
}

run "replication_enabled" {
  command = plan

  variables {
    replication_regions = ["eu-west-1", "ap-southeast-2"]
  }

  assert {
    condition = (
      [for d in aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].destination : d.region] == ["eu-west-1", "ap-southeast-2"] &&
      alltrue([for d in aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].destination : d.registry_id == "111122223333"])
    )
    error_message = "replication should target each Region in the caller's own registry"
  }
}

run "rejects_replication_to_own_region" {
  command         = plan
  expect_failures = [aws_ecr_replication_configuration.this]

  variables {
    replication_regions = ["us-east-1"]
  }
}

###############################################################################
# Validation
###############################################################################

run "rejects_bad_repository_name" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      "Bad_Name-" = {}
    }
  }
}

run "rejects_single_char_repository_name" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      a = {}
    }
  }
}

run "rejects_bad_mutability" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      app = { image_tag_mutability = "SOMETIMES" }
    }
  }
}

run "rejects_wildcard_principal" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      app = { pull_principals = ["*"] }
    }
  }
}

run "rejects_malformed_principal" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      app = { push_principals = ["arn:aws:sts::111122223333:assumed-role/x/y"] }
    }
  }
}

run "rejects_zero_untagged_expire_days" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      app = { untagged_expire_days = 0 }
    }
  }
}

run "rejects_zero_keep_tagged_count" {
  command         = plan
  expect_failures = [var.repositories]

  variables {
    repositories = {
      app = { keep_tagged_count = 0 }
    }
  }
}

run "rejects_zero_module_untagged_expire_days" {
  command         = plan
  expect_failures = [var.lifecycle_untagged_expire_days]

  variables {
    lifecycle_untagged_expire_days = 0
  }
}

run "rejects_bad_encryption_type" {
  command         = plan
  expect_failures = [var.encryption_type]

  variables {
    encryption_type = "SSE"
  }
}

run "rejects_kms_key_with_aes256" {
  command         = plan
  expect_failures = [var.kms_key_arn]

  variables {
    encryption_type = "AES256"
    kms_key_arn     = "arn:aws:kms:us-east-1:111122223333:key/EXAMPLE"
  }
}

run "rejects_kms_alias_as_key_arn" {
  command         = plan
  expect_failures = [var.kms_key_arn]

  variables {
    kms_key_arn = "alias/aws/ecr"
  }
}

run "rejects_continuous_scan_on_basic" {
  command         = plan
  expect_failures = [var.registry_scanning]

  variables {
    registry_scanning = {
      scan_type = "BASIC"
      rules     = [{ scan_frequency = "CONTINUOUS_SCAN" }]
    }
  }
}

run "rejects_bad_scan_type" {
  command         = plan
  expect_failures = [var.registry_scanning]

  variables {
    registry_scanning = {
      scan_type = "DEEP"
    }
  }
}

run "rejects_bad_pull_through_credential" {
  command         = plan
  expect_failures = [var.pull_through_cache_rules]

  variables {
    pull_through_cache_rules = {
      docker-hub = {
        upstream_registry_url = "registry-1.docker.io"
        credential_arn        = "arn:aws:secretsmanager:us-east-1:111122223333:secret:docker-hub-creds"
      }
    }
  }
}

run "rejects_bad_replication_region" {
  command         = plan
  expect_failures = [var.replication_regions]

  variables {
    replication_regions = ["Europe"]
  }
}
