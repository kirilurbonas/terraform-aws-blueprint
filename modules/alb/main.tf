terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/alb"
    },
    var.tags,
  )

  name_prefix = "${var.name_prefix}-${var.environment}"

  # ALB and target group names are capped at 32 characters. Names that fit are
  # used as-is; longer ones are cut to 27 characters and given a 4-hex suffix
  # derived from the full name, so the result is deterministic and two long
  # names that share a prefix still differ.
  lb_full_name = "${local.name_prefix}-alb"
  lb_name      = length(local.lb_full_name) <= 32 ? local.lb_full_name : "${substr(local.lb_full_name, 0, 27)}-${substr(md5(local.lb_full_name), 0, 4)}"

  # Target groups always carry the suffix. It also hashes the attributes that
  # force replacement (port, protocol, target type, protocol version), so a
  # replacement gets a new name and create_before_destroy can stand up the new
  # group before the listener lets go of the old one.
  target_groups = {
    for key, tg in var.target_groups : key => merge(tg, {
      is_lambda = tg.target_type == "lambda"
      name = "${substr("${local.name_prefix}-${key}", 0, 27)}-${substr(md5(jsonencode([
        "${local.name_prefix}-${key}", tg.port, tg.protocol, tg.target_type, tg.protocol_version,
      ])), 0, 4)}"
    })
  }

  associate_web_acl = var.associate_web_acl != null ? var.associate_web_acl : var.web_acl_arn != null

  # Ingress rules: HTTPS always, HTTP only when it exists to redirect.
  listener_ports = merge(
    { https = 443 },
    var.http_redirect ? { http = 80 } : {},
  )

  ingress_cidr_rules = merge([
    for listener, port in local.listener_ports : {
      for cidr in var.ingress_cidr_blocks : "${listener}-${cidr}" => {
        port = port
        cidr = cidr
      }
    }
  ]...)

  ingress_prefix_list_rules = merge([
    for listener, port in local.listener_ports : {
      for label, id in var.ingress_prefix_list_ids : "${listener}-${label}" => {
        port  = port
        label = label
        id    = id
      }
    }
  ]...)
}

###############################################################################
# Security group
#
# Rules are separate aws_vpc_security_group_*_rule resources so each one is
# tagged and can change without replacing the others. With no egress rule
# resources, the group has no egress at all: Terraform removes the AWS default
# allow-all egress rule when it creates the group.
###############################################################################

resource "aws_security_group" "this" {
  name_prefix = "${local.name_prefix}-alb-"
  description = "Security group for ALB ${local.lb_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = local.ingress_cidr_rules

  security_group_id = aws_security_group.this.id
  description       = "ALB listener port ${each.value.port} from ${each.value.cidr}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-ingress-${each.key}"
  })
}

# Keys are caller-chosen labels, so prefix list IDs created in the same apply
# are accepted.
resource "aws_vpc_security_group_ingress_rule" "prefix_list" {
  for_each = local.ingress_prefix_list_rules

  security_group_id = aws_security_group.this.id
  description       = "ALB listener port ${each.value.port} from prefix list ${each.value.label}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  prefix_list_id    = each.value.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-ingress-${each.key}"
  })
}

resource "aws_vpc_security_group_egress_rule" "vpc" {
  security_group_id = aws_security_group.this.id
  description       = "ALB to targets and health checks inside the VPC"
  ip_protocol       = "tcp"
  from_port         = var.egress_port_range.from_port
  to_port           = var.egress_port_range.to_port
  cidr_ipv4         = var.vpc_cidr

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-egress-vpc"
  })
}

# Keys are caller-chosen labels, so target security group IDs created in the
# same apply are accepted.
resource "aws_vpc_security_group_egress_rule" "security_group" {
  for_each = var.egress_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "ALB to targets in security group ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.egress_port_range.from_port
  to_port                      = var.egress_port_range.to_port
  referenced_security_group_id = each.value

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-egress-${each.key}"
  })
}

###############################################################################
# Load balancer
###############################################################################

resource "aws_lb" "this" {
  name               = local.lb_name
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.this.id]

  # Reject requests whose header names are not valid HTTP tokens instead of
  # forwarding them; closes off a class of request-smuggling attacks. Not
  # configurable on purpose.
  drop_invalid_header_fields = true
  desync_mitigation_mode     = var.desync_mitigation_mode
  enable_http2               = true
  idle_timeout               = var.idle_timeout
  preserve_host_header       = var.preserve_host_header
  xff_header_processing_mode = var.xff_header_processing_mode
  enable_deletion_protection = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.access_logs != null ? [var.access_logs] : []
    content {
      enabled = true
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
    }
  }

  dynamic "connection_logs" {
    for_each = var.connection_logs != null ? [var.connection_logs] : []
    content {
      enabled = true
      bucket  = connection_logs.value.bucket
      prefix  = connection_logs.value.prefix
    }
  }

  tags = merge(local.common_tags, {
    Name = local.lb_name
  })
}

###############################################################################
# Target groups
###############################################################################

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = each.value.name
  target_type = each.value.target_type

  # Lambda target groups take no port, protocol, protocol version or VPC.
  port             = each.value.is_lambda ? null : each.value.port
  protocol         = each.value.is_lambda ? null : each.value.protocol
  protocol_version = each.value.is_lambda ? null : each.value.protocol_version
  vpc_id           = each.value.is_lambda ? null : var.vpc_id

  deregistration_delay = each.value.deregistration_delay

  health_check {
    enabled             = each.value.health_check.enabled
    path                = each.value.health_check.path
    port                = each.value.is_lambda ? null : each.value.health_check.port
    protocol            = each.value.is_lambda ? null : coalesce(each.value.health_check.protocol, each.value.protocol)
    matcher             = coalesce(each.value.health_check.matcher, each.value.protocol_version == "GRPC" ? "12" : "200-399")
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness != null ? [each.value.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = stickiness.value.cookie_duration
      cookie_name     = stickiness.value.type == "app_cookie" ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.common_tags, {
    Name = each.value.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# HTTPS listener
#
# Default action is a fixed 404 so that requests matching no listener rule do
# not reach a backend, unless default_target_group_key names a target group.
###############################################################################

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  dynamic "default_action" {
    for_each = var.default_target_group_key == null ? [1] : []
    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.default_target_group_key != null ? [var.default_target_group_key] : []
    content {
      type             = "forward"
      target_group_arn = try(aws_lb_target_group.this[default_action.value].arn, null)
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-https"
  })

  lifecycle {
    precondition {
      condition     = var.default_target_group_key == null || contains(keys(var.target_groups), coalesce(var.default_target_group_key, "-"))
      error_message = "default_target_group_key must be a key of target_groups."
    }
  }
}

resource "aws_lb_listener_certificate" "this" {
  for_each = var.additional_certificate_arns

  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = each.value
}

###############################################################################
# HTTP listener (optional)
#
# Exists only to send clients to HTTPS. It never forwards to a target group.
###############################################################################

resource "aws_lb_listener" "http" {
  count = var.http_redirect ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-http"
  })
}

###############################################################################
# Listener rules (HTTPS listener)
###############################################################################

resource "aws_lb_listener_rule" "this" {
  for_each = var.listener_rules

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = try(aws_lb_target_group.this[each.value.target_group_key].arn, null)
  }

  dynamic "condition" {
    for_each = length(each.value.host_header) > 0 ? [each.value.host_header] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_pattern) > 0 ? [each.value.path_pattern] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-rule-${each.key}"
  })

  lifecycle {
    precondition {
      condition     = contains(keys(var.target_groups), each.value.target_group_key)
      error_message = "listener_rules.${each.key}.target_group_key \"${each.value.target_group_key}\" is not a key of target_groups."
    }
  }
}

###############################################################################
# WAFv2 association (optional)
#
# count must be known at plan time. `web_acl_arn != null` is unknown when the
# web ACL is created in the same apply, so associate_web_acl lets the caller
# state the intent explicitly in that case.
###############################################################################

resource "aws_wafv2_web_acl_association" "this" {
  count = local.associate_web_acl ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn

  lifecycle {
    precondition {
      condition     = var.web_acl_arn != null
      error_message = "associate_web_acl = true requires web_acl_arn."
    }
  }
}
