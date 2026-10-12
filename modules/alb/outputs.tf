output "lb_arn" {
  description = "Load balancer ARN."
  value       = aws_lb.this.arn
}

output "lb_arn_suffix" {
  description = "Load balancer ARN suffix, the LoadBalancer dimension for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "lb_dns_name" {
  description = "Load balancer DNS name (target of a Route 53 alias record)."
  value       = aws_lb.this.dns_name
}

output "lb_zone_id" {
  description = "Route 53 hosted zone ID of the load balancer, for alias records."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "Security group attached to the load balancer. Reference it from target security groups to admit ALB traffic."
  value       = aws_security_group.this.id
}

output "https_listener_arn" {
  description = "HTTPS listener ARN. Attach further listener rules here."
  value       = aws_lb_listener.https.arn
}

output "http_listener_arn" {
  description = "HTTP redirect listener ARN. Null when http_redirect = false."
  value       = try(aws_lb_listener.http[0].arn, null)
}

output "target_group_arns" {
  description = "Map of target_groups key => target group ARN."
  value       = { for key, tg in aws_lb_target_group.this : key => tg.arn }
}

output "target_group_arn_suffixes" {
  description = "Map of target_groups key => target group ARN suffix, the TargetGroup dimension for CloudWatch metrics."
  value       = { for key, tg in aws_lb_target_group.this : key => tg.arn_suffix }
}
