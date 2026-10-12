# "Tagging is a contract" (README, design principles), enforced on the plan
# instead of by convention. Applies to every managed resource that exposes a
# `tags` argument.
package main

import data.lib.terraform as tf
import rego.v1

required_tags := {"Environment", "ManagedBy", "Project"}

deny contains msg if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action == "create"
	a := rc.change.after
	"tags" in object.keys(a)
	tags := tags_of(a)
	some key in required_tags
	not key in object.keys(tags)
	msg := sprintf("%s: missing required tag %q", [rc.address, key])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.mode == "managed"
	tags := object.get(rc.change.after, "tags", {})
	is_object(tags)
	tags.ManagedBy
	tags.ManagedBy != "Terraform"
	msg := sprintf("%s: ManagedBy tag must be \"Terraform\"", [rc.address])
}

# `tags` is null when a resource sets none at all.
tags_of(a) := a.tags if is_object(a.tags)

tags_of(a) := {} if not is_object(a.tags)
