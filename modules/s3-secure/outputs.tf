output "bucket_id" {
  description = "Bucket name (also the bucket ID)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket domain name (used in legacy virtual-hosted-style URLs)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional bucket domain name. Prefer this over bucket_domain_name in modern AWS regions."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Route53 hosted zone ID for the bucket's region (handy when fronting with CloudFront)."
  value       = aws_s3_bucket.this.hosted_zone_id
}
