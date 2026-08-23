###############################################################################
# Override file: Terraform merges these blocks on top of the resources defined
# in the called modules. Use this to bolt `prevent_destroy = true` onto
# stateful resources for prod stacks without modifying the upstream module.
#
# Note: an override targeting a *resource inside a child module* needs the
# resource address to match exactly. The blocks below illustrate the pattern;
# uncomment and adapt to your module versions.
#
# In Terraform 1.5+ the cleaner pattern is to define a `removed` /
# `import` block for cross-module manipulation. For prevent_destroy
# specifically, this override style remains the canonical workaround.
###############################################################################

# Uncomment when you actually want prevent_destroy enforced. We leave it
# commented in this example so `terraform validate` passes for callers who
# don't yet have these resources in state.
#
# moved {
#   from = module.rds.aws_db_instance.this
#   to   = module.rds.aws_db_instance.this
# }
#
# resource "aws_db_instance" "this" {
#   # Address must match the module's resource. Empty body just lifts the
#   # primary configuration; the lifecycle block is what we're adding.
#   lifecycle {
#     prevent_destroy = true
#   }
# }
#
# resource "aws_s3_bucket" "this" {
#   lifecycle {
#     prevent_destroy = true
#   }
# }
