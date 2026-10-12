# IAM invariants. Policies whose JSON is unknown at plan time (computed from
# resources created in the same apply) are skipped, not guessed at; the module
# tests cover their construction.
package main

import data.lib.terraform as tf
import rego.v1

admin_policy_arns := {
	"arn:aws:iam::aws:policy/AdministratorAccess",
	"arn:aws:iam::aws:policy/PowerUserAccess",
	"arn:aws:iam::aws:policy/IAMFullAccess",
}

deny contains msg if {
	some rc in tf.resources("aws_iam_role_policy_attachment")
	some arn in admin_policy_arns
	endswith(tf.after(rc).policy_arn, trim_prefix(arn, "arn:aws"))
	msg := sprintf("%s: attaches %s — no role in this library gets admin", [rc.address, tf.after(rc).policy_arn])
}

inline_policy_types := {"aws_iam_role_policy", "aws_iam_policy"}

# Allow statements granting every action are the textbook escalation path.
deny contains msg if {
	some type in inline_policy_types
	some rc in tf.resources(type)
	doc := tf.policy_doc(tf.after(rc).policy)
	some stmt in tf.statements(doc)
	stmt.Effect == "Allow"
	some action in tf.as_list(object.get(stmt, "Action", []))
	action in {"*", "*:*"}
	msg := sprintf("%s: Allow statement grants Action \"*\"", [rc.address])
}

# Trust policies must not let any principal assume the role.
deny contains msg if {
	some rc in tf.resources("aws_iam_role")
	doc := tf.policy_doc(tf.after(rc).assume_role_policy)
	some stmt in tf.statements(doc)
	stmt.Effect == "Allow"
	open_principal(stmt.Principal)
	msg := sprintf("%s: trust policy allows any principal to assume the role", [rc.address])
}

open_principal(p) if p == "*"

open_principal(p) if {
	some aws in tf.as_list(p.AWS)
	aws == "*"
}

# A web-identity trust without a `sub` condition lets every identity the
# provider issues assume the role (every GitHub repository, every service
# account in the cluster).
deny contains msg if {
	some rc in tf.resources("aws_iam_role")
	doc := tf.policy_doc(tf.after(rc).assume_role_policy)
	some stmt in tf.statements(doc)
	stmt.Effect == "Allow"
	"sts:AssumeRoleWithWebIdentity" in tf.as_list(stmt.Action)
	not has_sub_condition(stmt)
	msg := sprintf("%s: web-identity trust must be scoped with a :sub condition", [rc.address])
}

has_sub_condition(stmt) if {
	some _, conds in stmt.Condition
	some key, _ in conds
	endswith(key, ":sub")
}
