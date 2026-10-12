# 0001 — EKS cluster access through Access Entries, not `aws-auth`

**Status:** Accepted (v0.2.0)

## Context

Until 2023 the only way to map IAM principals to Kubernetes identities was the
`aws-auth` ConfigMap in `kube-system`. Managing it from Terraform requires the
`kubernetes` provider, configured from the outputs of the cluster being
created in the same apply — a well-known source of provider-configuration
cycles, and a ConfigMap that a stray `kubectl edit` can break, locking every
node and human out of the cluster.

EKS Access Entries (GA December 2023) move the same mapping into the EKS API:
`aws_eks_access_entry` and `aws_eks_access_policy_association` are ordinary
AWS resources.

## Decision

The `eks` module manages access only through Access Entries.
`authentication_mode` defaults to `API` and accepts `API_AND_CONFIG_MAP` only
as a migration step; `CONFIG_MAP` alone is rejected. The module does not
depend on the `kubernetes` provider and never reads or writes `aws-auth`. Managed node groups get their access entry
automatically from EKS.

## Consequences

- Applying the module needs only AWS credentials — no cluster reachability,
  no second provider, no two-phase apply.
- Access is auditable in CloudTrail and cannot be broken from inside the
  cluster.
- Clusters created before Access Entries that still use `CONFIG_MAP` mode must
  migrate (`API_AND_CONFIG_MAP` first, then `API`) before adopting this module.
  That migration is one-way.
