# Architecture decision records

Decisions that shape the library's interface or defaults, recorded so they are
argued once. Each record states the context at the time, the decision, and
what it costs. A superseded record stays in place with a pointer to its
replacement.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-eks-access-entries.md) | EKS cluster access through Access Entries, not `aws-auth` | Accepted |
| [0002](0002-plan-only-tests.md) | Plan-only tests against `mock_provider`; no real-AWS apply in CI | Accepted |
| [0003](0003-policy-on-plan-json.md) | Policy-as-code evaluated on plan JSON, planned against Moto | Accepted |
| [0004](0004-opt-in-then-flip.md) | Secure-default changes ship opt-in, flip at a major version | Accepted |
| [0005](0005-workload-identity.md) | Pod Identity alongside IRSA; IRSA stays the default until 1.0 | Accepted |
| [0006](0006-s3-native-state-locking.md) | S3-native state locking replaces DynamoDB | Accepted |
| [0007](0007-static-keys-for-computed-ids.md) | `for_each` keys must be known at plan time | Accepted |

New records: copy the shape of an existing one, take the next number, and add
a row here in the same PR as the change it justifies.
