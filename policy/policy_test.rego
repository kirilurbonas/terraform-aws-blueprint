# Unit tests for the plan policies: `conftest verify --policy policy`.
#
# Each invariant gets a violating fixture (the rule must fire) and, where the
# rule has an exemption, a fixture proving the exemption holds. The plans of
# the examples are the "known good" side, evaluated by `make policy`.
package main

import rego.v1

tags := {"Environment": "dev", "ManagedBy": "Terraform", "Project": "t"}

change(type, after) := change_in("", type, after)

change_in(mod, type, after) := {
	"address": sprintf("%s.this", [type]),
	"module_address": mod,
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": object.union({"tags": tags}, after)},
}

plan(changes) := {"resource_changes": changes}

# --- network -------------------------------------------------------------------

test_ssh_from_internet_denied if {
	count(deny) > 0 with input as plan([change("aws_vpc_security_group_ingress_rule", {
		"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 22, "to_port": 22,
	})])
}

test_all_traffic_from_internet_denied if {
	count(deny) > 0 with input as plan([change("aws_vpc_security_group_ingress_rule", {
		"cidr_ipv6": "::/0", "ip_protocol": "-1", "from_port": null, "to_port": null,
	})])
}

test_https_from_internet_only_warns if {
	inp := plan([change("aws_vpc_security_group_ingress_rule", {
		"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 443, "to_port": 443,
	})])
	count(deny) == 0 with input as inp
	count(warn) == 1 with input as inp
}

test_ssh_from_vpc_allowed if {
	count(deny) == 0 with input as plan([change("aws_vpc_security_group_ingress_rule", {
		"cidr_ipv4": "10.0.0.0/16", "ip_protocol": "tcp", "from_port": 22, "to_port": 22,
	})])
}

test_inline_rdp_denied if {
	count(deny) > 0 with input as plan([change("aws_security_group", {"ingress": [{
		"cidr_blocks": ["0.0.0.0/0"], "from_port": 3000, "to_port": 4000,
	}]})])
}

# --- storage -------------------------------------------------------------------

locked_pab := {
	"block_public_acls": true, "block_public_policy": true,
	"ignore_public_acls": true, "restrict_public_buckets": true,
}

test_bucket_without_pab_denied if {
	count(deny) > 0 with input as plan([
		change_in("module.s3", "aws_s3_bucket", {}),
		change_in("module.s3", "aws_s3_bucket_server_side_encryption_configuration", {}),
	])
}

test_bucket_with_partial_pab_denied if {
	count(deny) > 0 with input as plan([
		change_in("module.s3", "aws_s3_bucket", {}),
		change_in("module.s3", "aws_s3_bucket_public_access_block", object.union(locked_pab, {"block_public_policy": false})),
		change_in("module.s3", "aws_s3_bucket_server_side_encryption_configuration", {}),
	])
}

test_bucket_with_companions_allowed if {
	count(deny) == 0 with input as plan([
		change_in("module.s3", "aws_s3_bucket", {}),
		change_in("module.s3", "aws_s3_bucket_public_access_block", locked_pab),
		change_in("module.s3", "aws_s3_bucket_server_side_encryption_configuration", {}),
	])
}

# A locked bucket in one module must not vouch for an open one in another.
test_pab_does_not_cross_modules if {
	count(deny) > 0 with input as plan([
		change_in("module.a", "aws_s3_bucket", {}),
		change_in("module.a", "aws_s3_bucket_server_side_encryption_configuration", {}),
		change_in("module.b", "aws_s3_bucket_public_access_block", locked_pab),
	])
}

test_bucket_acls_denied if {
	count(deny) > 0 with input as plan([change("aws_s3_bucket_ownership_controls", {
		"rule": [{"object_ownership": "ObjectWriter"}],
	})])
}

test_public_rds_denied if {
	count(deny) > 0 with input as plan([change("aws_db_instance", {
		"publicly_accessible": true, "storage_encrypted": true, "replicate_source_db": null,
	})])
}

test_unencrypted_rds_denied if {
	count(deny) > 0 with input as plan([change("aws_db_instance", {
		"publicly_accessible": false, "storage_encrypted": false, "replicate_source_db": null,
	})])
}

test_replica_inherits_encryption if {
	count(deny) == 0 with input as plan([change("aws_db_instance", {
		"publicly_accessible": false, "storage_encrypted": null, "replicate_source_db": "arn:aws:rds:x",
	})])
}

test_unencrypted_aurora_denied if {
	count(deny) > 0 with input as plan([change("aws_rds_cluster", {"storage_encrypted": false})])
}

test_unencrypted_ebs_denied if {
	count(deny) > 0 with input as plan([change("aws_launch_template", {
		"metadata_options": [{"http_tokens": "required"}],
		"block_device_mappings": [{"device_name": "/dev/xvda", "ebs": [{"encrypted": "false"}]}],
	})])
}

test_kms_without_rotation_denied if {
	count(deny) > 0 with input as plan([change("aws_kms_key", {"enable_key_rotation": false})])
}

test_asymmetric_kms_exempt_from_rotation if {
	count(deny) == 0 with input as plan([change("aws_kms_key", {
		"enable_key_rotation": false, "key_spec": "RSA_2048",
	})])
}

test_log_group_without_retention_denied if {
	count(deny) > 0 with input as plan([change("aws_cloudwatch_log_group", {"retention_in_days": 0})])
}

# --- compute -------------------------------------------------------------------

test_imdsv1_denied if {
	count(deny) > 0 with input as plan([change("aws_launch_template", {
		"metadata_options": [{"http_tokens": "optional"}], "block_device_mappings": [],
	})])
}

test_node_group_without_launch_template_denied if {
	count(deny) > 0 with input as plan([change("aws_eks_node_group", {"launch_template": []})])
}

test_eks_without_secrets_encryption_denied if {
	count(deny) > 0 with input as plan([change("aws_eks_cluster", {
		"encryption_config": [],
		"vpc_config": [{"endpoint_public_access": false}],
	})])
}

test_eks_open_public_endpoint_denied if {
	count(deny) > 0 with input as plan([change("aws_eks_cluster", {
		"encryption_config": [{"resources": ["secrets"]}],
		"vpc_config": [{"endpoint_public_access": true, "public_access_cidrs": ["0.0.0.0/0"]}],
	})])
}

test_eks_restricted_public_endpoint_allowed if {
	count(deny) == 0 with input as plan([change("aws_eks_cluster", {
		"encryption_config": [{"resources": ["secrets"]}],
		"vpc_config": [{"endpoint_public_access": true, "public_access_cidrs": ["203.0.113.0/24"]}],
	})])
}

test_alb_keeping_invalid_headers_denied if {
	count(deny) > 0 with input as plan([change("aws_lb", {
		"load_balancer_type": "application", "drop_invalid_header_fields": false,
	})])
}

test_http_listener_forwarding_denied if {
	count(deny) > 0 with input as plan([change("aws_lb_listener", {
		"protocol": "HTTP", "default_action": [{"type": "forward"}],
	})])
}

test_http_listener_redirect_allowed if {
	count(deny) == 0 with input as plan([change("aws_lb_listener", {
		"protocol": "HTTP", "default_action": [{"type": "redirect"}],
	})])
}

test_tls12_listener_denied if {
	count(deny) > 0 with input as plan([change("aws_lb_listener", {
		"protocol": "HTTPS", "ssl_policy": "ELBSecurityPolicy-2016-08",
		"default_action": [{"type": "forward"}],
	})])
}

# --- iam -----------------------------------------------------------------------

test_admin_attachment_denied if {
	count(deny) > 0 with input as plan([change("aws_iam_role_policy_attachment", {
		"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess",
	})])
}

test_admin_attachment_denied_in_govcloud if {
	count(deny) > 0 with input as plan([change("aws_iam_role_policy_attachment", {
		"policy_arn": "arn:aws-us-gov:iam::aws:policy/AdministratorAccess",
	})])
}

test_star_action_denied if {
	count(deny) > 0 with input as plan([change("aws_iam_role_policy", {
		"policy": json.marshal({"Version": "2012-10-17", "Statement": [{
			"Effect": "Allow", "Action": "*", "Resource": "*",
		}]}),
	})])
}

test_unknown_policy_skipped if {
	count(deny) == 0 with input as plan([change("aws_iam_role_policy", {})])
}

test_open_trust_denied if {
	count(deny) > 0 with input as plan([change("aws_iam_role", {
		"assume_role_policy": json.marshal({"Statement": {
			"Effect": "Allow", "Action": "sts:AssumeRole", "Principal": {"AWS": "*"},
		}}),
	})])
}

test_web_identity_without_sub_denied if {
	count(deny) > 0 with input as plan([change("aws_iam_role", {
		"assume_role_policy": json.marshal({"Statement": [{
			"Effect": "Allow",
			"Action": "sts:AssumeRoleWithWebIdentity",
			"Principal": {"Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"},
			"Condition": {"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"}},
		}]}),
	})])
}

test_web_identity_with_sub_allowed if {
	count(deny) == 0 with input as plan([change("aws_iam_role", {
		"assume_role_policy": json.marshal({"Statement": [{
			"Effect": "Allow",
			"Action": "sts:AssumeRoleWithWebIdentity",
			"Principal": {"Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"},
			"Condition": {
				"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
				"StringLike": {"token.actions.githubusercontent.com:sub": "repo:acme/app:ref:refs/heads/main"},
			},
		}]}),
	})])
}

# --- tagging -------------------------------------------------------------------

test_missing_tag_denied if {
	count(deny) > 0 with input as plan([{
		"address": "aws_sqs_queue.q", "mode": "managed", "type": "aws_sqs_queue",
		"change": {"actions": ["create"], "after": {"tags": {"Environment": "dev"}}},
	}])
}

test_null_tags_denied if {
	count(deny) > 0 with input as plan([{
		"address": "aws_sqs_queue.q", "mode": "managed", "type": "aws_sqs_queue",
		"change": {"actions": ["create"], "after": {"tags": null}},
	}])
}

test_untaggable_resource_ignored if {
	count(deny) == 0 with input as plan([{
		"address": "aws_route.r", "mode": "managed", "type": "aws_route",
		"change": {"actions": ["create"], "after": {"destination_cidr_block": "0.0.0.0/0"}},
	}])
}

test_deleted_resources_ignored if {
	count(deny) == 0 with input as plan([{
		"address": "aws_kms_key.k", "mode": "managed", "type": "aws_kms_key",
		"change": {"actions": ["delete"], "after": null},
	}])
}
