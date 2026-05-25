# example: full-stack

End-to-end reference deployment that ties every blueprint module together:

```
            ┌────────────────────────────────────────────────┐
            │                      VPC                       │
            │  3 AZ • per-AZ NAT • Flow Logs to S3           │
            └───────┬──────────────────┬────────────┬────────┘
                    │ private subnets  │            │ private subnets
                    ▼                  ▼            ▼
            ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
            │     EKS      │   │     RDS      │  │  S3 secure   │
            │  control     │   │ postgres 16  │  │  artifacts   │
            │  + nodes     │   │   multi-AZ   │  │  bucket      │
            └──────┬───────┘   └──────────────┘  └──────┬───────┘
                   │ OIDC                                ▲
                   ▼                                     │
            ┌──────────────────────────────────────────────┐
            │ IRSA role → ServiceAccount app/app           │
            │  s3:Get/Put/Delete on the artifacts bucket   │
            └──────────────────────────────────────────────┘
```

Wiring highlights:

- EKS nodes live in the VPC's private subnets.
- RDS lives in the same private subnets; its security group only permits the
  EKS node security group on the Postgres port.
- A secure S3 bucket holds application artifacts.
- An IRSA role binds the `app/app` Kubernetes ServiceAccount to scoped
  read/write permissions on the artifacts bucket — no static keys, no
  node-wide IAM access.

## Usage

```bash
cd examples/full-stack
terraform init
terraform apply
```

After apply:

```bash
$(terraform output -raw kubeconfig_command)

# Annotate the application ServiceAccount so it gets AWS credentials:
kubectl create namespace app
kubectl create sa app -n app
kubectl annotate sa app -n app \
  "eks.amazonaws.com/role-arn=$(terraform output -raw app_irsa_role_arn)"
```

The RDS master password is in Secrets Manager — read the ARN from
`rds_master_secret_arn` and fetch it from the application via
`secretsmanager:GetSecretValue` (grant via a second IRSA binding when needed).
