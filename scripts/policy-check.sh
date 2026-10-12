#!/usr/bin/env bash
# Plan every example against a local AWS API emulator and evaluate the plan
# JSON with the Conftest policies in policy/.
#
# Why a real plan and not HCL: policies need resolved values — variable
# defaults, module wiring, conditionals — which only exist after planning. The
# AWS provider calls the API during plan for a handful of data sources
# (availability zones, caller identity) and for credential validation, so the
# plan runs against Moto (https://github.com/getmoto/moto) via
# AWS_ENDPOINT_URL. Nothing is created; no AWS account or credentials are
# involved.
#
# Usage: scripts/policy-check.sh [example-dir ...]   (default: examples/*)
#
# Env:
#   MOTO_PORT       port for the emulator (default 5055)
#   MOTO_SERVER     moto_server binary (default: moto_server on PATH)
#   PLAN_OUT_DIR    where plan JSON is written (default: .policy-plans)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

port=${MOTO_PORT:-5055}
moto=${MOTO_SERVER:-moto_server}
out=${PLAN_OUT_DIR:-$root/.policy-plans}
mkdir -p "$out"

if [ "$#" -gt 0 ]; then
  examples=("$@")
else
  examples=(examples/*/)
fi

command -v conftest >/dev/null || { echo "conftest not found (https://www.conftest.dev/install/)" >&2; exit 1; }
command -v "$moto" >/dev/null || { echo "$moto not found — pip install 'moto[server]'" >&2; exit 1; }

"$moto" -p "$port" >"$out/moto.log" 2>&1 &
moto_pid=$!
trap 'kill "$moto_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:${port}/moto-api/" >/dev/null && break
  sleep 0.2
done
curl -sf "http://127.0.0.1:${port}/moto-api/" >/dev/null || { echo "moto did not start; see $out/moto.log" >&2; exit 1; }

export AWS_ENDPOINT_URL="http://127.0.0.1:${port}"
export AWS_ACCESS_KEY_ID=policy-check AWS_SECRET_ACCESS_KEY=policy-check
export AWS_EC2_METADATA_DISABLED=true
export TF_IN_AUTOMATION=1 TF_INPUT=0
unset AWS_PROFILE AWS_SESSION_TOKEN

plans=()
for dir in "${examples[@]}"; do
  dir=${dir%/}
  name=$(basename "$dir")
  echo "==> plan $dir"
  terraform -chdir="$dir" init -backend=false -lockfile=readonly -no-color >/dev/null
  # -refresh=false: there is no prior state, and refresh would only add API
  # calls the emulator has nothing meaningful to answer with.
  terraform -chdir="$dir" plan -refresh=false -no-color -out="$out/$name.tfplan" >/dev/null
  terraform -chdir="$dir" show -json "$out/$name.tfplan" >"$out/$name.json"
  rm -f "$out/$name.tfplan"
  plans+=("$out/$name.json")
done

echo "==> conftest"
conftest test --policy policy --no-color "${plans[@]}"
