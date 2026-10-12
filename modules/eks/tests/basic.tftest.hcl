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

run "oidc_provider_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 1
    error_message = "the IRSA OIDC provider should be created by default"
  }
}

run "oidc_provider_can_be_disabled" {
  command = plan

  variables {
    create_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 0
    error_message = "no OIDC provider should be planned when create_oidc_provider = false"
  }

  assert {
    condition     = output.oidc_provider_arn == null
    error_message = "oidc_provider_arn should be null when create_oidc_provider = false"
  }
}

run "pod_identity_associations_are_created" {
  command = plan

  variables {
    cluster_addons = {
      eks-pod-identity-agent = {}
    }
    pod_identity_associations = {
      external_dns = {
        namespace       = "kube-system"
        service_account = "external-dns"
        role_arn        = "arn:aws:iam::111122223333:role/external-dns"
      }
      app = {
        namespace       = "apps"
        service_account = "api"
        role_arn        = "arn:aws:iam::111122223333:role/api"
      }
    }
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 2
    error_message = "expected one pod identity association per map entry"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["external_dns"].service_account == "external-dns"
    error_message = "pod identity association should target the configured service account"
  }
}

run "addon_passthrough_values_are_applied" {
  command = plan

  variables {
    cluster_addons = {
      aws-ebs-csi-driver = {
        service_account_role_arn = "arn:aws:iam::111122223333:role/ebs-csi"
        configuration_values     = "{\"controller\":{\"replicaCount\":2}}"
      }
    }
  }

  assert {
    condition     = aws_eks_addon.this["aws-ebs-csi-driver"].service_account_role_arn == "arn:aws:iam::111122223333:role/ebs-csi"
    error_message = "service_account_role_arn should be passed through to the add-on"
  }

  assert {
    condition     = jsondecode(aws_eks_addon.this["aws-ebs-csi-driver"].configuration_values).controller.replicaCount == 2
    error_message = "configuration_values should be passed through to the add-on"
  }
}

run "upgrade_policy_and_zonal_shift_are_omitted_by_default" {
  command = plan

  assert {
    condition     = length(aws_eks_cluster.this.upgrade_policy) == 0 && length(aws_eks_cluster.this.zonal_shift_config) == 0
    error_message = "upgrade_policy and zonal_shift_config should not be set unless requested"
  }
}

run "upgrade_policy_and_zonal_shift_are_set" {
  command = plan

  variables {
    upgrade_policy     = { support_type = "STANDARD" }
    zonal_shift_config = { enabled = true }
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "upgrade_policy.support_type should be passed through"
  }

  assert {
    condition     = aws_eks_cluster.this.zonal_shift_config[0].enabled == true
    error_message = "zonal_shift_config.enabled should be passed through"
  }
}

run "rejects_bad_upgrade_support_type" {
  command         = plan
  expect_failures = [var.upgrade_policy]

  variables {
    upgrade_policy = { support_type = "LTS" }
  }
}

run "rejects_bad_addon_configuration_values" {
  command         = plan
  expect_failures = [var.cluster_addons]

  variables {
    cluster_addons = {
      coredns = {
        configuration_values = "{\"replicaCount\": 2"
      }
    }
  }
}

run "rejects_bad_addon_role_arn" {
  command         = plan
  expect_failures = [var.cluster_addons]

  variables {
    cluster_addons = {
      aws-ebs-csi-driver = {
        service_account_role_arn = "ebs-csi"
      }
    }
  }
}

run "rejects_bad_addon_resolve_conflicts_on_create" {
  command         = plan
  expect_failures = [var.cluster_addons]

  variables {
    cluster_addons = {
      coredns = {
        resolve_conflicts_on_create = "PRESERVE"
      }
    }
  }
}

run "rejects_bad_addon_resolve_conflicts_on_update" {
  command         = plan
  expect_failures = [var.cluster_addons]

  variables {
    cluster_addons = {
      coredns = {
        resolve_conflicts_on_update = "KEEP"
      }
    }
  }
}

run "rejects_bad_pod_identity_namespace" {
  command         = plan
  expect_failures = [var.pod_identity_associations]

  variables {
    pod_identity_associations = {
      app = {
        namespace       = "Apps_NS"
        service_account = "api"
        role_arn        = "arn:aws:iam::111122223333:role/api"
      }
    }
  }
}

run "rejects_bad_pod_identity_service_account" {
  command         = plan
  expect_failures = [var.pod_identity_associations]

  variables {
    pod_identity_associations = {
      app = {
        namespace       = "apps"
        service_account = "API_SA"
        role_arn        = "arn:aws:iam::111122223333:role/api"
      }
    }
  }
}

run "rejects_bad_pod_identity_role_arn" {
  command         = plan
  expect_failures = [var.pod_identity_associations]

  variables {
    pod_identity_associations = {
      app = {
        namespace       = "apps"
        service_account = "api"
        role_arn        = "arn:aws:iam::111122223333:user/api"
      }
    }
  }
}

run "rejects_duplicate_pod_identity_service_account" {
  command         = plan
  expect_failures = [var.pod_identity_associations]

  variables {
    pod_identity_associations = {
      first = {
        namespace       = "apps"
        service_account = "api"
        role_arn        = "arn:aws:iam::111122223333:role/api-a"
      }
      second = {
        namespace       = "apps"
        service_account = "api"
        role_arn        = "arn:aws:iam::111122223333:role/api-b"
      }
    }
  }
}
