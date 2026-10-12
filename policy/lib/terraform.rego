# Helpers shared by every policy package. Input is the JSON form of a saved
# plan (`terraform show -json plan.bin`), so these walk `resource_changes`
# rather than HCL source: what is checked is what Terraform would actually
# create, after variables, defaults, and module wiring have been resolved.
package lib.terraform

import rego.v1

# Managed resources that the plan will create or update. Deletes and no-ops
# are skipped — a policy should not fail a plan for a resource it is removing.
resources(type) := [rc |
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.type == type
	some action in rc.change.actions
	action in {"create", "update"}
]

after(rc) := rc.change.after

# The module path a resource lives in ("" for the root module). Used to pair
# companion resources (bucket + public access block) that sit side by side in
# the same module call.
module_of(rc) := rc.module_address

module_of(rc) := "" if not rc.module_address

# True when a CIDR opens the rule to the whole internet.
world_cidr(rule) if rule.cidr_ipv4 == "0.0.0.0/0"

world_cidr(rule) if rule.cidr_ipv6 == "::/0"

# True when a security-group rule's port range includes `port`. Protocol "-1"
# (all traffic) carries no ports and covers everything.
covers_port(rule, _) if rule.ip_protocol == "-1"

covers_port(rule, port) if {
	rule.ip_protocol in {"tcp", "6"}
	rule.from_port <= port
	port <= rule.to_port
}

# Parse a policy attribute that may be a JSON string, already-decoded object,
# or unknown at plan time (absent from `after`). Unknown policies are skipped
# rather than guessed at.
policy_doc(raw) := json.unmarshal(raw) if is_string(raw)

policy_doc(raw) := raw if is_object(raw)

# Statements normalised to a list; a document may carry a single statement
# object instead of an array.
statements(doc) := doc.Statement if is_array(doc.Statement)

statements(doc) := [doc.Statement] if is_object(doc.Statement)

as_list(x) := x if is_array(x)

as_list(x) := [x] if not is_array(x)
