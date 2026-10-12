mock_provider "aws" {}

variables {
  name_prefix = "test"
  environment = "dev"
  project     = "blueprint-tests"
  vpc_id      = "vpc-0123456789abcdef0"
  vpc_cidr    = "10.0.0.0/16"
  subnet_ids = [
    "subnet-0000000000000000a",
    "subnet-0000000000000000b",
  ]
  certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
}

run "defaults_plan_cleanly" {
  command = plan

  assert {
    condition     = aws_lb.this.load_balancer_type == "application" && aws_lb.this.internal == false
    error_message = "default should be an internet-facing application load balancer"
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "deletion protection must be on by default"
  }

  assert {
    condition     = aws_lb.this.desync_mitigation_mode == "strictest" && aws_lb.this.enable_http2 == true
    error_message = "desync mitigation must default to strictest and HTTP/2 must be enabled"
  }

  assert {
    condition     = aws_lb.this.name == "test-dev-alb"
    error_message = "load balancer name should be <name_prefix>-<environment>-alb"
  }

  assert {
    condition     = aws_lb.this.tags["ManagedBy"] == "Terraform" && aws_lb.this.tags["Module"] == "terraform-aws-blueprint/alb"
    error_message = "common tags must be applied"
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0 && length(aws_lb.this.connection_logs) == 0
    error_message = "access and connection logs should be off unless a bucket is given"
  }
}

run "drops_invalid_header_fields" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "drop_invalid_header_fields must always be true"
  }
}

run "http_listener_only_redirects" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.http) == 1
    error_message = "http_redirect = true should create the HTTP listener"
  }

  assert {
    condition = alltrue([
      for a in aws_lb_listener.http[0].default_action :
      a.type == "redirect" && a.redirect[0].protocol == "HTTPS" && a.redirect[0].port == "443" && a.redirect[0].status_code == "HTTP_301"
    ])
    error_message = "HTTP listener must only 301-redirect to HTTPS:443"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.cidr) == 2
    error_message = "one CIDR should yield ingress on 443 and 80"
  }
}

run "http_redirect_disabled" {
  command = plan

  variables {
    http_redirect = false
  }

  assert {
    condition     = length(aws_lb_listener.http) == 0 && output.http_listener_arn == null
    error_message = "http_redirect = false should create no HTTP listener"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.cidr) == 1 && aws_vpc_security_group_ingress_rule.cidr["https-0.0.0.0/0"].from_port == 443
    error_message = "without the redirect only port 443 should be open"
  }
}

run "https_listener_defaults" {
  command = plan

  assert {
    condition     = aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.https.protocol == "HTTPS"
    error_message = "HTTPS listener must default to the TLS 1.3 policy"
  }

  assert {
    condition     = aws_lb_listener.https.default_action[0].type == "fixed-response" && aws_lb_listener.https.default_action[0].fixed_response[0].status_code == "404"
    error_message = "HTTPS default action must be a fixed 404 when no default target group is set"
  }
}

run "security_group_rules" {
  command = plan

  variables {
    ingress_prefix_list_ids = { cloudfront = "pl-82a045eb" }
    egress_security_groups  = { eks_nodes = "sg-0123456789abcdef0" }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.prefix_list) == 2
    error_message = "a prefix list should be admitted on 443 and 80"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.vpc.cidr_ipv4 == "10.0.0.0/16" && aws_vpc_security_group_egress_rule.vpc.ip_protocol == "tcp"
    error_message = "egress must be restricted to the VPC CIDR over TCP"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.security_group["eks_nodes"].referenced_security_group_id == "sg-0123456789abcdef0"
    error_message = "egress_security_groups should produce one egress rule per label"
  }
}

run "target_groups_and_rules_fan_out" {
  command = plan

  variables {
    target_groups = {
      api = {
        port = 8080
        health_check = {
          path = "/healthz"
        }
      }
      grpc = {
        port             = 50051
        protocol_version = "GRPC"
        stickiness = {
          type = "lb_cookie"
        }
      }
      fn = {
        target_type = "lambda"
      }
    }
    listener_rules = {
      api = {
        priority         = 10
        target_group_key = "api"
        host_header      = ["api.example.com"]
        path_pattern     = ["/v1/*"]
      }
      grpc = {
        priority         = 20
        target_group_key = "grpc"
        host_header      = ["grpc.example.com"]
      }
    }
    default_target_group_key = "api"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 3 && length(aws_lb_listener_rule.this) == 2
    error_message = "expected one target group per target_groups entry and one rule per listener_rules entry"
  }

  assert {
    condition     = aws_lb_target_group.this["api"].target_type == "ip" && aws_lb_target_group.this["api"].port == 8080 && aws_lb_target_group.this["api"].health_check[0].path == "/healthz"
    error_message = "target group defaults and overrides should both apply"
  }

  assert {
    condition     = aws_lb_target_group.this["grpc"].health_check[0].matcher == "12" && aws_lb_target_group.this["api"].health_check[0].matcher == "200-399"
    error_message = "health check matcher should default per protocol version"
  }

  assert {
    condition     = aws_lb_target_group.this["fn"].port == null && aws_lb_target_group.this["fn"].vpc_id == null
    error_message = "lambda target groups take no port or VPC"
  }

  assert {
    condition     = alltrue([for tg in aws_lb_target_group.this : length(tg.name) <= 32 && startswith(tg.name, "test-dev-")])
    error_message = "target group names must be <= 32 chars and carry the name prefix"
  }

  assert {
    condition     = aws_lb_listener_rule.this["api"].priority == 10 && length(aws_lb_listener_rule.this["api"].condition) == 2
    error_message = "the api rule should carry host and path conditions"
  }

  assert {
    condition     = aws_lb_listener.https.default_action[0].type == "forward"
    error_message = "default_target_group_key should switch the default action to forward"
  }
}

run "long_names_are_truncated_deterministically" {
  command = plan

  variables {
    name_prefix = "a-long-platform-name-xyz"
    environment = "staging"
    target_groups = {
      checkout-service-primary = {}
    }
  }

  assert {
    condition     = length(aws_lb.this.name) == 32 && length(aws_lb_target_group.this["checkout-service-primary"].name) == 32
    error_message = "names over 32 chars must be truncated to exactly 32"
  }

  assert {
    condition     = aws_lb.this.name == "a-long-platform-name-xyz-st-${substr(md5("a-long-platform-name-xyz-staging-alb"), 0, 4)}"
    error_message = "the ALB name suffix must be derived from the full name"
  }
}

run "logs_enabled" {
  command = plan

  variables {
    access_logs     = { bucket = "my-alb-logs", prefix = "alb" }
    connection_logs = { bucket = "my-alb-logs", prefix = "alb-conn" }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].enabled == true && aws_lb.this.access_logs[0].bucket == "my-alb-logs"
    error_message = "access logs should be enabled when a bucket is given"
  }

  assert {
    condition     = aws_lb.this.connection_logs[0].enabled == true && aws_lb.this.connection_logs[0].prefix == "alb-conn"
    error_message = "connection logs should be enabled when a bucket is given"
  }
}

run "waf_association_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "no WAF association without web_acl_arn"
  }
}

run "waf_association_when_set" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:111122223333:regional/webacl/edge/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "web_acl_arn should create the WAF association"
  }
}

run "waf_association_explicit_toggle" {
  command = plan

  variables {
    web_acl_arn       = "arn:aws:wafv2:us-east-1:111122223333:regional/webacl/edge/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
    associate_web_acl = false
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "associate_web_acl = false should override an inferred association"
  }
}

run "additional_certificates" {
  command = plan

  variables {
    additional_certificate_arns = {
      legacy = "arn:aws:acm:us-east-1:111122223333:certificate/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = length(aws_lb_listener_certificate.this) == 1
    error_message = "each additional certificate should be attached to the HTTPS listener"
  }
}

###############################################################################
# Validation and precondition failures
###############################################################################

run "rejects_non_tls13_ssl_policy" {
  command         = plan
  expect_failures = [var.ssl_policy]

  variables {
    ssl_policy = "ELBSecurityPolicy-2016-08"
  }
}

run "rejects_single_subnet" {
  command         = plan
  expect_failures = [var.subnet_ids]

  variables {
    subnet_ids = ["subnet-0000000000000000a"]
  }
}

run "rejects_bad_certificate_arn" {
  command         = plan
  expect_failures = [var.certificate_arn]

  variables {
    certificate_arn = "arn:aws:s3:::not-a-certificate"
  }
}

run "rejects_bad_target_protocol" {
  command         = plan
  expect_failures = [var.target_groups]

  variables {
    target_groups = {
      api = { protocol = "TCP" }
    }
  }
}

run "rejects_bad_target_type" {
  command         = plan
  expect_failures = [var.target_groups]

  variables {
    target_groups = {
      api = { target_type = "alb" }
    }
  }
}

run "rejects_app_cookie_without_name" {
  command         = plan
  expect_failures = [var.target_groups]

  variables {
    target_groups = {
      api = {
        stickiness = { type = "app_cookie" }
      }
    }
  }
}

run "rejects_out_of_range_priority" {
  command         = plan
  expect_failures = [var.listener_rules]

  variables {
    target_groups = { api = {} }
    listener_rules = {
      api = {
        priority         = 50001
        target_group_key = "api"
        path_pattern     = ["/*"]
      }
    }
  }
}

run "rejects_rule_without_conditions" {
  command         = plan
  expect_failures = [var.listener_rules]

  variables {
    target_groups = { api = {} }
    listener_rules = {
      api = {
        priority         = 1
        target_group_key = "api"
      }
    }
  }
}

run "rejects_rule_with_unknown_target_group" {
  command         = plan
  expect_failures = [aws_lb_listener_rule.this]

  variables {
    target_groups = { api = {} }
    listener_rules = {
      web = {
        priority         = 1
        target_group_key = "web"
        path_pattern     = ["/*"]
      }
    }
  }
}

run "rejects_unknown_default_target_group" {
  command         = plan
  expect_failures = [aws_lb_listener.https]

  variables {
    default_target_group_key = "missing"
  }
}

run "rejects_bad_idle_timeout" {
  command         = plan
  expect_failures = [var.idle_timeout]

  variables {
    idle_timeout = 5000
  }
}

run "rejects_bad_desync_mode" {
  command         = plan
  expect_failures = [var.desync_mitigation_mode]

  variables {
    desync_mitigation_mode = "off"
  }
}

run "rejects_bucket_arn_for_access_logs" {
  command         = plan
  expect_failures = [var.access_logs]

  variables {
    access_logs = { bucket = "arn:aws:s3:::my-alb-logs" }
  }
}

run "rejects_waf_toggle_without_arn" {
  command         = plan
  expect_failures = [aws_wafv2_web_acl_association.this]

  variables {
    associate_web_acl = true
  }
}
