# example: eks-cluster

Provisions a VPC plus an EKS cluster wired to it. Nodes run in private subnets;
the API endpoint is private by default.

## Usage

```bash
cd examples/eks-cluster
terraform init
terraform apply
```

To turn on the public endpoint (e.g. for kubectl from a laptop) without losing
private access:

```bash
terraform apply -var endpoint_public_access=true
```

After apply, get a kubeconfig:

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

## Approximate monthly cost

| Item | Cost (us-east-1) |
|------|------------------|
| EKS control plane | $73 |
| 3 NAT gateways (per-AZ) | ~$96 |
| 2 × t3.large nodes (on-demand) | ~$120 |
| 5 interface endpoints × 3 AZs | ~$32 |
| EBS, CloudWatch logs, NAT data | variable |
| **Total** | **~$320/mo + traffic** |

This is the cluster the README says it is — production-shaped, not a toy.
Drop `interface_endpoints = []` and `nat_gateway_mode = "single"` in your
own copy to halve the bill for a sandbox. Run `terraform destroy` when done.
