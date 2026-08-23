# Shared tflint configuration for the whole tree.
#
# Both CI (`tflint --recursive`) and the pre-commit hook read this file, so a
# rule enabled here is enforced in both places. Do not re-specify rules with
# `--only` on the command line — that silently narrows the rule set and was the
# reason the AWS ruleset never ran before v0.3.0.

config {
  # Lint the modules that examples call, not just the example's own files.
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# `preset = "all"` turns on terraform_naming_convention with the default
# snake_case expectation, which is what this repo already follows.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}
