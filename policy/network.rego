# Network invariants that hold across every module and example, independent
# of how a particular stack is wired.
package main

import data.lib.terraform as tf
import rego.v1

admin_ports := {22, 3389}

# No security group may expose SSH or RDP to the internet. Nodes are reached
# through SSM Session Manager; there is no bastion pattern in this library.
deny contains msg if {
	some rc in tf.resources("aws_vpc_security_group_ingress_rule")
	rule := tf.after(rc)
	tf.world_cidr(rule)
	some port in admin_ports
	tf.covers_port(rule, port)
	msg := sprintf("%s: ingress from the internet covers admin port %d", [rc.address, port])
}

# Inline ingress blocks on aws_security_group bypass the rule resources above;
# check them too so a consumer cannot route around the policy.
deny contains msg if {
	some rc in tf.resources("aws_security_group")
	some rule in object.get(tf.after(rc), "ingress", [])
	some cidr in object.get(rule, "cidr_blocks", [])
	cidr == "0.0.0.0/0"
	some port in admin_ports
	rule.from_port <= port
	port <= rule.to_port
	msg := sprintf("%s: inline ingress from 0.0.0.0/0 covers admin port %d", [rc.address, port])
}

# Ingress open to the world on any other port is legitimate only on a load
# balancer. Surface it so the reviewer sees it, without failing the plan.
warn contains msg if {
	some rc in tf.resources("aws_vpc_security_group_ingress_rule")
	rule := tf.after(rc)
	tf.world_cidr(rule)
	not admin_port_rule(rule)
	msg := sprintf("%s: ingress open to the internet (ports %v-%v)", [rc.address, rule.from_port, rule.to_port])
}

admin_port_rule(rule) if {
	some port in admin_ports
	tf.covers_port(rule, port)
}

# Every VPC that ships flow logs must actually attach them.
deny contains msg if {
	some rc in tf.resources("aws_flow_log")
	tf.after(rc).traffic_type == null
	msg := sprintf("%s: flow log has no traffic_type", [rc.address])
}
