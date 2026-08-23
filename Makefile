# Local development entry points. CI calls these same targets, so a green
# `make all` locally means a green pipeline — the two cannot drift.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT       := $(shell git rev-parse --show-toplevel)
MODULES    := $(wildcard modules/*)
EXAMPLES   := $(wildcard examples/*)
ALL_DIRS   := $(MODULES) $(EXAMPLES)

# `tflint --recursive` re-reads config from each working directory. Without an
# absolute config path every subdirectory falls back to the bundled terraform
# ruleset and the AWS ruleset silently never runs.
export TFLINT_CONFIG_FILE := $(ROOT)/.tflint.hcl

# The floor of the `aws` provider constraint the modules declare. `make
# validate-floor` pins to it so a module that starts depending on a newer
# provider feature fails here, not in a consumer's stack.
AWS_PROVIDER_FLOOR ?= 6.0.0

.DEFAULT_GOAL := help
.PHONY: help fmt fmt-check validate validate-floor lint test docs docs-check security all clean

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

fmt: ## Rewrite all Terraform files to canonical format
	terraform fmt -recursive

fmt-check: ## Fail if any Terraform file is not canonically formatted
	terraform fmt -check -recursive -diff

validate: ## terraform init + validate every module and example
	@for d in $(MODULES); do \
		echo "==> validate $$d"; \
		( cd "$$d" && terraform init -backend=false -no-color >/dev/null && terraform validate -no-color ); \
	done
	@for d in $(EXAMPLES); do \
		echo "==> validate $$d"; \
		( cd "$$d" && terraform init -backend=false -lockfile=readonly -no-color >/dev/null && terraform validate -no-color ); \
	done

validate-floor: ## Validate every module against the declared provider floor
	@tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	for d in $(MODULES); do \
		name=$$(basename "$$d"); \
		echo "==> validate $$d @ aws $(AWS_PROVIDER_FLOOR)"; \
		cp -R "$$d" "$$tmp/$$name"; \
		rm -rf "$$tmp/$$name/.terraform" "$$tmp/$$name/.terraform.lock.hcl"; \
		printf 'terraform {\n  required_providers {\n    aws = {\n      source  = "hashicorp/aws"\n      version = "%s"\n    }\n  }\n}\n' "$(AWS_PROVIDER_FLOOR)" > "$$tmp/$$name/zz_provider_floor_override.tf"; \
		( cd "$$tmp/$$name" && terraform init -backend=false -no-color >/dev/null && terraform validate -no-color ); \
	done

lint: ## tflint across the tree, with the shared rule set
	tflint --init
	@tflint --version | grep -q 'ruleset.aws' || { echo "AWS ruleset did not load — check .tflint.hcl"; exit 1; }
	tflint --recursive --minimum-failure-severity=warning

test: ## Plan-only module tests against mock_provider
	@for d in $(MODULES); do \
		if compgen -G "$$d/tests/*.tftest.hcl" > /dev/null; then \
			echo "==> test $$d"; \
			( cd "$$d" && terraform init -backend=false -no-color >/dev/null && terraform test -no-color ); \
		fi; \
	done

docs: ## Regenerate the terraform-docs block in every README
	@for d in $(ALL_DIRS); do \
		echo "==> docs $$d"; \
		terraform-docs --config "$(ROOT)/.terraform-docs.yml" "$$d"; \
	done

docs-check: ## Fail if regenerating docs would change anything
	@snap=$$(mktemp -d); trap 'rm -rf "$$snap"' EXIT; \
	for d in $(ALL_DIRS); do \
		mkdir -p "$$snap/$$d"; cp "$$d/README.md" "$$snap/$$d/README.md"; \
	done; \
	$(MAKE) --no-print-directory docs >/dev/null; \
	rc=0; \
	for d in $(ALL_DIRS); do \
		if ! diff -q "$$snap/$$d/README.md" "$$d/README.md" >/dev/null; then \
			echo "stale docs: $$d/README.md"; \
			diff -u "$$snap/$$d/README.md" "$$d/README.md" || true; \
			rc=1; \
		fi; \
	done; \
	if [ "$$rc" -ne 0 ]; then \
		echo "terraform-docs output is stale — run 'make docs' and commit the result"; \
	fi; \
	exit $$rc

security: ## Trivy misconfiguration scan, gating on HIGH/CRITICAL
	# --ignorefile is required: Trivy auto-discovers .trivyignore but not the
	# .trivyignore.yaml form, and the YAML form is what carries the written
	# justification for each suppression.
	# Offline fallback if the checks-bundle download stalls: add
	# --skip-check-update to use the checks embedded in the binary. Note that
	# the embedded set reports check IDs without the AVD- prefix, which is why
	# .trivyignore.yaml lists both forms.
	# If the bundle download hangs on ghcr.io, add
	# --checks-bundle-repository mirror.gcr.io/aquasec/trivy-checks:1
	trivy config . \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--skip-dirs '**/.terraform' \
		--ignorefile .trivyignore.yaml

all: fmt-check validate validate-floor lint test docs-check security ## Everything CI runs

clean: ## Remove local .terraform directories
	find modules examples -type d -name .terraform -prune -exec rm -rf {} +
