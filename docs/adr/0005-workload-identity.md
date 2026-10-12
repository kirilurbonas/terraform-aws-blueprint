# 0005 — Pod Identity alongside IRSA

**Status:** Accepted (v0.4.0)

## Context

IRSA (IAM Roles for Service Accounts) needs an IAM OIDC provider per cluster
and a role trust policy that names that provider and the service account. A
role used by workloads in several clusters must list every cluster's provider
in its trust policy, and the 100-OIDC-provider-per-account quota becomes a
real limit for fleets.

EKS Pod Identity (GA November 2023) uses a single service principal
(`pods.eks.amazonaws.com`) in the trust policy and binds role to service
account with an `aws_eks_pod_identity_association` — an EKS API object, so
the binding lives with the cluster rather than in the role.

## Decision

The `eks` module supports both:

- `pod_identity_associations` creates associations; the
  `eks-pod-identity-agent` add-on runs the credential endpoint on each node.
- `create_oidc_provider` (default `true`) keeps IRSA available. Setting it to
  `false` removes the OIDC provider for clusters that have fully moved to Pod
  Identity.

IRSA stays the default until 1.0 so existing clusters see no change
([0004](0004-opt-in-then-flip.md)).

## Consequences

- New workloads should use Pod Identity; the module README shows both
  patterns side by side.
- Some workloads cannot use Pod Identity (Fargate pods, a few third-party
  controllers that assume IRSA). That is why the OIDC provider remains
  available rather than being removed.
- Turning off the OIDC provider on a live cluster breaks every IRSA role that
  trusts it. The README calls this out.
