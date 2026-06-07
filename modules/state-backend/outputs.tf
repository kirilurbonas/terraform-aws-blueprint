output "bucket_name" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table."
  value       = aws_dynamodb_table.lock.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table."
  value       = aws_dynamodb_table.lock.arn
}

output "backend_config_hcl" {
  description = "Ready-to-paste `terraform { backend \"s3\" { ... } }` body for downstream stacks."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.id}"
    key            = "<stack-name>/terraform.tfstate"
    region         = "${data.aws_region.current.region}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    encrypt        = true
  EOT
}

data "aws_region" "current" {}
