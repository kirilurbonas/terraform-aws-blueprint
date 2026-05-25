# Remote state backend. Uncomment and fill in for shared environments.
#
# terraform {
#   backend "s3" {
#     bucket         = "my-tfstate-bucket"
#     key            = "terraform-aws-blueprint/examples/simple-vpc/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "tfstate-locks"
#     encrypt        = true
#   }
# }
