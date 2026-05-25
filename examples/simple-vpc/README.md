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
