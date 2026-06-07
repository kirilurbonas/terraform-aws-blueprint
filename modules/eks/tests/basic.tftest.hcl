mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix        = "test"
  environment        = "dev"
  project            = "blueprint-tests"
  kubernetes_version = "1.30"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0000000000000000a",
    "subnet-0000000000000000b",
  ]
  node_groups = {
    default = {
      desired_size = 2
      min_size     = 1
      max_size     = 3
    }
  }
}

run "defaults_plan_cleanly" {
  command = plan
}

run "multi_ng_creates_per_ng_resources" {
  command = plan

  variables {
    node_groups = {
      system = { desired_size = 2, min_size = 2, max_size = 4 }
      apps   = { desired_size = 3, min_size = 3, max_size = 9, capacity_type = "SPOT", instance_types = ["m6i.large", "m6a.large"] }
    }
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 2
    error_message = "expected one node group per map entry"
  }

  assert {
    condition     = length(aws_launch_template.node) == 2
    error_message = "expected one launch template per node group"
  }
}

run "ssm_policy_attached_once_for_shared_node_role" {
  command = plan

  variables {
    node_groups = {
      system = { desired_size = 2, min_size = 2, max_size = 4, enable_ssm_access = true }
      apps   = { desired_size = 3, min_size = 3, max_size = 9, enable_ssm_access = true }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.node_ssm) == 1
    error_message = "the shared node role should only receive one SSM policy attachment"
  }
}

run "addons_are_created" {
  command = plan

  variables {
    cluster_addons = {
      vpc-cni    = {}
      coredns    = {}
      kube-proxy = {}
    }
  }

  assert {
    condition     = length(aws_eks_addon.this) == 3
    error_message = "expected one aws_eks_addon per cluster_addons entry"
  }
}

run "rejects_old_k8s" {
  command         = plan
  expect_failures = [var.kubernetes_version]

  variables {
    kubernetes_version = "1.20"
  }
}

run "rejects_empty_node_groups" {
  command         = plan
  expect_failures = [var.node_groups]

  variables {
    node_groups = {}
  }
}

run "rejects_bad_scaling_bounds" {
  command         = plan
  expect_failures = [var.node_groups]

  variables {
    node_groups = {
      default = {
        desired_size = 1
        min_size     = 2
        max_size     = 3
      }
    }
  }
}

run "rejects_namespace_policy_without_namespaces" {
  command         = plan
  expect_failures = [var.access_entries]

  variables {
    access_entries = {
      namespace_admin = {
        principal_arn = "arn:aws:iam::111122223333:role/ns-admin"
        policy_associations = [
          {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
            access_scope = {
              type = "namespace"
            }
          },
        ]
      }
    }
  }
}
