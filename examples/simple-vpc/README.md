# example: simple-vpc

Smallest possible call into the `vpc` module — three AZs, a single shared NAT
gateway, no flow logs. Useful for spinning up a sandbox VPC.

## Usage

```bash
cd examples/simple-vpc
terraform init
terraform apply
```

To target a non-default region or CIDR:

```bash
terraform apply -var region=eu-west-1 -var vpc_cidr=10.50.0.0/16
```

To use a shared remote state, uncomment the `backend "s3"` block in
[backend.tf](backend.tf) and re-run `terraform init`.

## Approximate monthly cost

| Item | Cost (us-east-1) |
|------|------------------|
| 1 NAT gateway | ~$32 |
| Elastic IP (attached) | $0 |
| VPC + subnets + route tables | $0 |
| **Total** | **~$32/mo + NAT data processing** |

Run `terraform destroy` when you're done sandboxing.
