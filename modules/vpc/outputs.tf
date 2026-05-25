output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs, ordered to match `availability_zones`."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs, ordered to match `availability_zones`."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs. Empty when `enable_nat_gateway = false`."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs attached to the NAT gateways."
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs (one per AZ)."
  value       = aws_route_table.private[*].id
}

output "flow_logs_bucket_arn" {
  description = "ARN of the S3 bucket receiving VPC flow logs. Null when flow logs are disabled or a pre-existing bucket was passed in."
  value       = length(aws_s3_bucket.flow_logs) > 0 ? aws_s3_bucket.flow_logs[0].arn : null
}

output "availability_zones" {
  description = "Availability zones used by the module."
  value       = var.availability_zones
}
