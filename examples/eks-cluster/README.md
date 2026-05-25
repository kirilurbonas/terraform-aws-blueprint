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
