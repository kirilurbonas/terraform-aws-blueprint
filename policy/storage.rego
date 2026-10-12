# Data-at-rest invariants: S3, RDS, Aurora, EBS, KMS, CloudWatch Logs.
package main

import data.lib.terraform as tf
import rego.v1

# --- S3 ----------------------------------------------------------------------
#
# Bucket names are often unknown at plan time (bucket_prefix), so a public
# access block cannot be joined to its bucket by name. Every module in this
# library declares the companion resources next to the bucket, so the check is
# per module call: each module that creates N buckets must also create N fully
# locked public access blocks and N encryption configurations.

bucket_count(mod) := count([rc |
	some rc in tf.resources("aws_s3_bucket")
	tf.module_of(rc) == mod
])

locked_pab_count(mod) := count([rc |
	some rc in tf.resources("aws_s3_bucket_public_access_block")
	tf.module_of(rc) == mod
	a := tf.after(rc)
	a.block_public_acls
	a.block_public_policy
	a.ignore_public_acls
	a.restrict_public_buckets
])

sse_count(mod) := count([rc |
	some rc in tf.resources("aws_s3_bucket_server_side_encryption_configuration")
	tf.module_of(rc) == mod
])

bucket_modules contains tf.module_of(rc) if {
	some rc in tf.resources("aws_s3_bucket")
}

deny contains msg if {
	some mod in bucket_modules
	locked_pab_count(mod) < bucket_count(mod)
	msg := sprintf("%s: %d S3 bucket(s) but only %d fully-enabled public access block(s)", [mod, bucket_count(mod), locked_pab_count(mod)])
}

deny contains msg if {
	some mod in bucket_modules
	sse_count(mod) < bucket_count(mod)
	msg := sprintf("%s: %d S3 bucket(s) but only %d server-side encryption configuration(s)", [mod, bucket_count(mod), sse_count(mod)])
}

deny contains msg if {
	some rc in tf.resources("aws_s3_bucket_ownership_controls")
	some rule in tf.after(rc).rule
	rule.object_ownership != "BucketOwnerEnforced"
	msg := sprintf("%s: ACLs must stay disabled (object_ownership = BucketOwnerEnforced)", [rc.address])
}

# --- RDS / Aurora --------------------------------------------------------------

deny contains msg if {
	some rc in tf.resources("aws_db_instance")
	tf.after(rc).publicly_accessible == true
	msg := sprintf("%s: RDS instance must not be publicly accessible", [rc.address])
}

# Read replicas inherit encryption from their source and report
# storage_encrypted as null, so only primaries are checked.
deny contains msg if {
	some rc in tf.resources("aws_db_instance")
	a := tf.after(rc)
	object.get(a, "replicate_source_db", null) == null
	a.storage_encrypted != true
	msg := sprintf("%s: RDS storage must be encrypted", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_rds_cluster")
	tf.after(rc).storage_encrypted != true
	msg := sprintf("%s: Aurora cluster storage must be encrypted", [rc.address])
}

deny contains msg if {
	some rc in tf.resources("aws_rds_cluster_instance")
	tf.after(rc).publicly_accessible == true
	msg := sprintf("%s: Aurora instance must not be publicly accessible", [rc.address])
}

# --- EBS ---------------------------------------------------------------------

deny contains msg if {
	some rc in tf.resources("aws_launch_template")
	some bdm in tf.after(rc).block_device_mappings
	some ebs in bdm.ebs
	not ebs.encrypted in {true, "true"}
	msg := sprintf("%s: EBS volume %s must be encrypted", [rc.address, bdm.device_name])
}

# --- KMS ---------------------------------------------------------------------

deny contains msg if {
	some rc in tf.resources("aws_kms_key")
	a := tf.after(rc)
	object.get(a, "key_spec", "SYMMETRIC_DEFAULT") == "SYMMETRIC_DEFAULT"
	a.enable_key_rotation != true
	msg := sprintf("%s: symmetric KMS keys must have rotation enabled", [rc.address])
}

# --- CloudWatch Logs -------------------------------------------------------------

# Never-expiring log groups are an unbounded cost and a retention-policy
# violation waiting to happen.
deny contains msg if {
	some rc in tf.resources("aws_cloudwatch_log_group")
	object.get(tf.after(rc), "retention_in_days", 0) == 0
	msg := sprintf("%s: log group must set retention_in_days", [rc.address])
}
