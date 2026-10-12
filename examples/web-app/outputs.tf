###############################################################################
# Edge
###############################################################################

output "alb_dns_name" {
  description = "ALB DNS name. Point the domain at it with an alias (Route 53) or CNAME record."
  value       = module.alb.lb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID, for a Route 53 alias record."
  value       = module.alb.lb_zone_id
}

output "certificate_validation_records" {
  description = "DNS records to create so ACM can issue the certificate."
  value = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }
}

output "target_group_arn" {
  description = "Target group to register the service in (ECS service load_balancer block, or an EKS TargetGroupBinding)."
  value       = module.alb.target_group_arns["web"]
}

output "service_security_group_id" {
  description = "Security group to attach to the service's tasks or pods."
  value       = aws_security_group.service.id
}

###############################################################################
# Data
###############################################################################

output "database_endpoint" {
  description = "Aurora writer endpoint."
  value       = module.aurora.cluster_endpoint
}

output "database_reader_endpoint" {
  description = "Aurora reader endpoint."
  value       = module.aurora.reader_endpoint
}

output "database_secret_arn" {
  description = "RDS-managed Secrets Manager secret holding the master credentials."
  value       = module.aurora.master_user_secret_arn
}

###############################################################################
# Delivery
###############################################################################

output "ecr_repository_url" {
  description = "Image repository URL to push to."
  value       = one(values(module.ecr.repository_urls))
}

output "ci_role_arn" {
  description = "Role for GitHub Actions: aws-actions/configure-aws-credentials role-to-assume."
  value       = module.ci.ci_deployer_role_arn
}
