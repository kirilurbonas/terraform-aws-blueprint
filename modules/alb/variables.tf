variable "name_prefix" {
  type        = string
  description = "Prefix applied to all named resources."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,24}$", var.name_prefix))
    error_message = "name_prefix must be 1-24 chars, lowercase alphanumerics and hyphens."
  }

  validation {
    condition     = !startswith(var.name_prefix, "-") && !startswith("${var.name_prefix}-", "internal-")
    error_message = "name_prefix must not start with a hyphen or with \"internal-\" (ALB names cannot)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  type        = string
  description = "Project tag applied to every resource."
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}

###############################################################################
# Network
###############################################################################

variable "vpc_id" {
  type        = string
  description = "VPC the load balancer, its security group and its target groups live in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-xxxxxxxx)."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR of the VPC. The security group allows egress to it on egress_port_range, which covers ip and instance targets and their health checks."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("^[0-9.]+/[0-9]+$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the load balancer, in at least two Availability Zones. Public subnets for an internet-facing ALB, private subnets when internal = true."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets (an ALB requires two Availability Zones)."
  }

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "subnet_ids must contain subnet IDs (subnet-xxxxxxxx)."
  }
}

variable "internal" {
  type        = bool
  description = "Create an internal load balancer (private IPs only). false = internet-facing."
  default     = false
}

###############################################################################
# Security group
###############################################################################

variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to reach the listeners (443, and 80 when http_redirect = true). Narrow this for internal load balancers. Values must be known at plan time."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.ingress_cidr_blocks : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}

variable "ingress_prefix_list_ids" {
  type        = map(string)
  description = "Managed prefix lists allowed to reach the listeners, as label => prefix list ID (e.g. { cloudfront = \"pl-82a045eb\" }). Labels are for_each keys, so IDs may be computed in the same apply."
  default     = {}

  validation {
    condition     = alltrue([for label in keys(var.ingress_prefix_list_ids) : can(regex("^[a-z0-9_-]{1,32}$", label))])
    error_message = "ingress_prefix_list_ids keys must be 1-32 chars: lowercase alphanumerics, underscore, or hyphen."
  }
}

variable "egress_security_groups" {
  type        = map(string)
  description = "Target security groups the ALB may reach, as label => security group ID (e.g. { eks_nodes = module.eks.node_security_group_id }). Added on top of the VPC CIDR egress rule. Labels are for_each keys, so IDs may be computed in the same apply."
  default     = {}

  validation {
    condition     = alltrue([for label in keys(var.egress_security_groups) : can(regex("^[a-z0-9_-]{1,32}$", label))])
    error_message = "egress_security_groups keys must be 1-32 chars: lowercase alphanumerics, underscore, or hyphen."
  }
}

variable "egress_port_range" {
  type = object({
    from_port = number
    to_port   = number
  })
  description = "TCP port range the ALB may open to targets. The default covers any target port; narrow it when every target and health-check port is known."
  default = {
    from_port = 1
    to_port   = 65535
  }

  validation {
    condition     = var.egress_port_range.from_port >= 1 && var.egress_port_range.to_port <= 65535 && var.egress_port_range.from_port <= var.egress_port_range.to_port
    error_message = "egress_port_range must satisfy 1 <= from_port <= to_port <= 65535."
  }
}

###############################################################################
# Load balancer attributes
###############################################################################

variable "enable_deletion_protection" {
  type        = bool
  description = "Block deletion of the load balancer through the AWS API. Set false before destroying."
  default     = true
}

variable "idle_timeout" {
  type        = number
  description = "Seconds a connection may stay idle before the ALB closes it."
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000 && floor(var.idle_timeout) == var.idle_timeout
    error_message = "idle_timeout must be a whole number between 1 and 4000."
  }
}

variable "desync_mitigation_mode" {
  type        = string
  description = "How the ALB treats requests that may pose an HTTP desync risk: monitor, defensive, or strictest."
  default     = "strictest"

  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode must be one of: monitor, defensive, strictest."
  }
}

variable "preserve_host_header" {
  type        = bool
  description = "Forward the client's Host header to targets unchanged instead of rewriting the port."
  default     = false
}

variable "xff_header_processing_mode" {
  type        = string
  description = "How the ALB handles the X-Forwarded-For header: append, preserve, or remove."
  default     = "append"

  validation {
    condition     = contains(["append", "preserve", "remove"], var.xff_header_processing_mode)
    error_message = "xff_header_processing_mode must be one of: append, preserve, remove."
  }
}

variable "access_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "Ship access logs to this S3 bucket. The bucket policy must allow the regional ELB log delivery principal, and the bucket must use SSE-S3 (SSE-KMS is not supported). Null = no access logs."
  default     = null

  validation {
    condition     = var.access_logs == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", try(var.access_logs.bucket, "")))
    error_message = "access_logs.bucket must be an S3 bucket name, not an ARN."
  }

  validation {
    condition     = var.access_logs == null || try(var.access_logs.prefix, null) == null || try(!startswith(var.access_logs.prefix, "/") && !endswith(var.access_logs.prefix, "/") && !strcontains(var.access_logs.prefix, "AWSLogs"), false)
    error_message = "access_logs.prefix must not start or end with \"/\" or contain \"AWSLogs\"."
  }
}

variable "connection_logs" {
  type = object({
    bucket = string
    prefix = optional(string)
  })
  description = "Ship connection logs (client TLS handshake details) to this S3 bucket. Same bucket requirements as access_logs. Null = no connection logs."
  default     = null

  validation {
    condition     = var.connection_logs == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", try(var.connection_logs.bucket, "")))
    error_message = "connection_logs.bucket must be an S3 bucket name, not an ARN."
  }

  validation {
    condition     = var.connection_logs == null || try(var.connection_logs.prefix, null) == null || try(!startswith(var.connection_logs.prefix, "/") && !endswith(var.connection_logs.prefix, "/") && !strcontains(var.connection_logs.prefix, "AWSLogs"), false)
    error_message = "connection_logs.prefix must not start or end with \"/\" or contain \"AWSLogs\"."
  }
}

###############################################################################
# Listeners
###############################################################################

variable "certificate_arn" {
  type        = string
  description = "Default certificate for the HTTPS listener (ACM or IAM server certificate ARN)."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:(acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+|iam::[0-9]{12}:server-certificate/.+)$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN (arn:aws:acm:<region>:<account>:certificate/<id>) or an IAM server certificate ARN."
  }
}

variable "additional_certificate_arns" {
  type        = map(string)
  description = "Extra certificates for the HTTPS listener (SNI), as label => certificate ARN. Labels are for_each keys, so ARNs may be computed in the same apply."
  default     = {}

  validation {
    condition     = alltrue([for arn in values(var.additional_certificate_arns) : can(regex("^arn:aws[a-z-]*:(acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+|iam::[0-9]{12}:server-certificate/.+)$", arn))])
    error_message = "additional_certificate_arns values must be ACM certificate ARNs or IAM server certificate ARNs."
  }
}

variable "ssl_policy" {
  type        = string
  description = "Security policy for the HTTPS listener. Restricted to TLS 1.3 policies (ELBSecurityPolicy-TLS13-*)."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = startswith(var.ssl_policy, "ELBSecurityPolicy-TLS13")
    error_message = "ssl_policy must be a TLS 1.3 policy (starts with \"ELBSecurityPolicy-TLS13\")."
  }
}

variable "http_redirect" {
  type        = bool
  description = "Create an HTTP :80 listener that answers every request with a 301 redirect to HTTPS, and open port 80 on the security group. The HTTP listener never forwards."
  default     = true
}

variable "default_target_group_key" {
  type        = string
  description = "Key of target_groups that the HTTPS listener forwards to when no listener rule matches. Null = fixed 404 response."
  default     = null
}

###############################################################################
# Target groups
###############################################################################

variable "target_groups" {
  type = map(object({
    port                 = optional(number, 80)
    protocol             = optional(string, "HTTP")
    protocol_version     = optional(string, "HTTP1")
    target_type          = optional(string, "ip")
    deregistration_delay = optional(number, 30)
    health_check = optional(object({
      enabled             = optional(bool, true)
      path                = optional(string, "/")
      port                = optional(string, "traffic-port")
      protocol            = optional(string)
      matcher             = optional(string)
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    stickiness = optional(object({
      enabled         = optional(bool, true)
      type            = optional(string, "lb_cookie")
      cookie_duration = optional(number, 86400)
      cookie_name     = optional(string)
    }))
  }))
  description = <<-EOT
    Target groups keyed by short name (lowercase alphanumerics and hyphens).
    The AWS name is <name_prefix>-<environment>-<key>, cut to 27 characters,
    plus a 4-hex suffix. target_type = "ip" suits EKS (AWS Load Balancer
    Controller TargetGroupBinding) and ECS awsvpc tasks. For "lambda" targets,
    port / protocol / protocol_version are ignored and the caller must grant
    elasticloadbalancing.amazonaws.com lambda:InvokeFunction. health_check
    .protocol defaults to the group's protocol; health_check.matcher defaults
    to "200-399" ("12" for GRPC).
  EOT
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.target_groups) : can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", key))])
    error_message = "target_groups keys must be 1-32 chars of lowercase alphanumerics and hyphens, not starting or ending with a hyphen."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["HTTP", "HTTPS"], tg.protocol)])
    error_message = "target_groups protocol must be one of: HTTP, HTTPS."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["HTTP1", "HTTP2", "GRPC"], tg.protocol_version)])
    error_message = "target_groups protocol_version must be one of: HTTP1, HTTP2, GRPC."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["ip", "instance", "lambda"], tg.target_type)])
    error_message = "target_groups target_type must be one of: ip, instance, lambda."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : tg.port >= 1 && tg.port <= 65535])
    error_message = "target_groups port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : tg.deregistration_delay >= 0 && tg.deregistration_delay <= 3600])
    error_message = "target_groups deregistration_delay must be between 0 and 3600 seconds."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.health_check.protocol == null || contains(["HTTP", "HTTPS"], coalesce(tg.health_check.protocol, "HTTP"))
    ])
    error_message = "target_groups health_check.protocol must be one of: HTTP, HTTPS."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.health_check.interval >= 5 && tg.health_check.interval <= 300 &&
      tg.health_check.timeout >= 2 && tg.health_check.timeout <= 120 &&
      tg.health_check.timeout < tg.health_check.interval
    ])
    error_message = "target_groups health_check: interval must be 5-300, timeout 2-120, and timeout less than interval."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.health_check.healthy_threshold >= 2 && tg.health_check.healthy_threshold <= 10 &&
      tg.health_check.unhealthy_threshold >= 2 && tg.health_check.unhealthy_threshold <= 10
    ])
    error_message = "target_groups health_check thresholds must be between 2 and 10."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.stickiness == null || try(contains(["lb_cookie", "app_cookie"], tg.stickiness.type), false)
    ])
    error_message = "target_groups stickiness.type must be one of: lb_cookie, app_cookie."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.stickiness == null || try(tg.stickiness.type != "app_cookie" || tg.stickiness.cookie_name != null, false)
    ])
    error_message = "target_groups stickiness.cookie_name is required when stickiness.type = app_cookie."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      tg.stickiness == null || try(tg.stickiness.cookie_duration >= 1 && tg.stickiness.cookie_duration <= 604800, false)
    ])
    error_message = "target_groups stickiness.cookie_duration must be between 1 and 604800 seconds."
  }
}

###############################################################################
# Listener rules
###############################################################################

variable "listener_rules" {
  type = map(object({
    priority         = number
    target_group_key = string
    host_header      = optional(list(string), [])
    path_pattern     = optional(list(string), [])
  }))
  description = "Forward rules on the HTTPS listener, keyed by short name. Each rule needs at least one host_header or path_pattern value (at most 5 values in total) and forwards matching requests to target_groups[target_group_key]."
  default     = {}

  validation {
    condition     = alltrue([for r in values(var.listener_rules) : r.priority >= 1 && r.priority <= 50000 && floor(r.priority) == r.priority])
    error_message = "listener_rules priority must be a whole number between 1 and 50000."
  }

  validation {
    condition     = length(distinct([for r in values(var.listener_rules) : r.priority])) == length(var.listener_rules)
    error_message = "listener_rules priorities must be unique."
  }

  validation {
    condition     = alltrue([for r in values(var.listener_rules) : length(r.host_header) + length(r.path_pattern) >= 1])
    error_message = "Each listener_rules entry must set at least one host_header or path_pattern value."
  }

  validation {
    condition     = alltrue([for r in values(var.listener_rules) : length(r.host_header) + length(r.path_pattern) <= 5])
    error_message = "Each listener_rules entry may set at most 5 host_header + path_pattern values in total."
  }
}

###############################################################################
# WAF
###############################################################################

variable "web_acl_arn" {
  type        = string
  description = "WAFv2 web ACL (REGIONAL scope) to associate with the load balancer. Null = no association. When the ARN is computed in the same apply, also set associate_web_acl = true."
  default     = null

  validation {
    condition     = var.web_acl_arn == null || can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/.+$", coalesce(var.web_acl_arn, "-")))
    error_message = "web_acl_arn must be a REGIONAL WAFv2 web ACL ARN (arn:aws:wafv2:<region>:<account>:regional/webacl/<name>/<id>)."
  }
}

variable "associate_web_acl" {
  type        = bool
  description = "Whether to create the WAFv2 association. Null = infer from web_acl_arn != null, which only works when the ARN is known at plan time; set true when the web ACL is created in the same apply."
  default     = null
}
