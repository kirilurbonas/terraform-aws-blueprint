# EKS and load-balancer invariants.
package main

import data.lib.terraform as tf
import rego.v1

# IMDSv2 is enforced through the launch template; a node group without one
# falls back to the AMI default, which permits IMDSv1.
deny contains msg if {
	some rc in tf.resources("aws_eks_node_group")
	count(object.get(tf.after(rc), "launch_template", [])) == 0
	msg := sprintf("%s: node group must use a launch template (IMDSv2 enforcement)", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_launch_template")
	some md in tf.after(rc).metadata_options
	md.http_tokens != "required"
	msg := sprintf("%s: IMDSv2 must be required (metadata_options.http_tokens = \"required\")", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_launch_template")
	count(object.get(tf.after(rc), "metadata_options", [])) == 0
	msg := sprintf("%s: launch template must set metadata_options with http_tokens = \"required\"", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_eks_cluster")
	count(object.get(tf.after(rc), "encryption_config", [])) == 0
	msg := sprintf("%s: EKS secrets must use KMS envelope encryption", [rc.address])
}

# A public API endpoint is allowed, but not one reachable from everywhere.
deny contains msg if {
	some rc in tf.resources("aws_eks_cluster")
	some vpc in tf.after(rc).vpc_config
	vpc.endpoint_public_access == true
	some cidr in object.get(vpc, "public_access_cidrs", ["0.0.0.0/0"])
	cidr == "0.0.0.0/0"
	msg := sprintf("%s: public EKS API endpoint must be restricted with public_access_cidrs", [rc.address])
}

# --- Load balancers ------------------------------------------------------------

deny contains msg if {
	some rc in tf.resources("aws_lb")
	a := tf.after(rc)
	object.get(a, "load_balancer_type", "application") == "application"
	a.drop_invalid_header_fields != true
	msg := sprintf("%s: ALB must drop invalid header fields (request smuggling)", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_lb_listener")
	a := tf.after(rc)
	a.protocol == "HTTP"
	some action in a.default_action
	action.type != "redirect"
	msg := sprintf("%s: plaintext HTTP listener must only redirect to HTTPS", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_lb_listener")
	a := tf.after(rc)
	a.protocol == "HTTPS"
	not startswith(object.get(a, "ssl_policy", ""), "ELBSecurityPolicy-TLS13")
	msg := sprintf("%s: HTTPS listener must use a TLS 1.3 security policy", [rc.address])
}

# --- ECR -----------------------------------------------------------------------

deny contains msg if {
	some rc in tf.resources("aws_ecr_repository")
	some enc in object.get(tf.after(rc), "encryption_configuration", [])
	not enc.encryption_type in {"KMS", "KMS_DSSE", "AES256"}
	msg := sprintf("%s: ECR repository must be encrypted", [rc.address])
}
