# alb

Application Load Balancer for EKS and ECS workloads: an HTTPS listener with a
TLS 1.3 security policy, an HTTP listener that only redirects to HTTPS, a
module-managed security group, target groups and host/path listener rules
declared as maps, and an optional WAFv2 association.

## Features

- `drop_invalid_header_fields = true` (not configurable) and
  `desync_mitigation_mode = "strictest"` by default
- HTTP/2 enabled; deletion protection on by default
- HTTPS listener restricted to `ELBSecurityPolicy-TLS13-*` policies (default
  `ELBSecurityPolicy-TLS13-1-2-2021-06`); extra SNI certificates via
  `additional_certificate_arns`
- HTTPS default action is a fixed `404` unless `default_target_group_key` names
  a target group, so unmatched requests never reach a backend by accident
- Optional HTTP `:80` listener that answers every request with a `301` to
  HTTPS and never forwards
- Security group with v5 `aws_vpc_security_group_*_rule` resources: ingress on
  443 (and 80 with the redirect) from CIDRs and/or managed prefix lists;
  egress only to the VPC CIDR and to caller-named target security groups
- Target groups (`ip`, `instance`, `lambda`) with per-group health checks and
  optional stickiness; names stay within the 32-character limit
- Listener rules on the HTTPS listener matching `host_header` and/or
  `path_pattern`
- Optional access logs and connection logs to S3
- Optional WAFv2 web ACL association

## Usage

```hcl
module "alb" {
  source = "github.com/kirilurbonas/terraform-aws-blueprint//modules/alb?ref=v0.4.0"

  name_prefix = "platform"
  environment = "prod"
  project     = "blueprint"

  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr_block
  subnet_ids = module.vpc.public_subnet_ids

  certificate_arn = aws_acm_certificate.app.arn

  egress_security_groups = {
    eks_nodes = module.eks.node_security_group_id
  }

  access_logs = {
    bucket = "platform-prod-alb-logs"
    prefix = "app"
  }

  target_groups = {
    api = {
      port = 8080
      health_check = {
        path = "/healthz"
      }
    }
    web = {
      port = 3000
    }
  }

  listener_rules = {
    api = {
      priority         = 10
      target_group_key = "api"
      host_header      = ["api.example.com"]
    }
    web = {
      priority         = 20
      target_group_key = "web"
      host_header      = ["www.example.com"]
      path_pattern     = ["/*"]
    }
  }

  web_acl_arn       = aws_wafv2_web_acl.edge.arn
  associate_web_acl = true
}
```

### Registering targets

The module creates target groups but registers no targets. On EKS, bind a
Kubernetes Service to a target group with the AWS Load Balancer Controller's
`TargetGroupBinding`, using `module.alb.target_group_arns["api"]`. On ECS, pass
the ARN to the service's `load_balancer` block. Both use `target_type = "ip"`,
the default.

Targets must admit traffic from the ALB: add an ingress rule on the target
security group referencing `module.alb.security_group_id`.

### Computed IDs and plan-time values

`ingress_prefix_list_ids`, `egress_security_groups` and
`additional_certificate_arns` are maps with caller-chosen keys, so their
values may be created in the same apply. `ingress_cidr_blocks` is a list used
as a `for_each` set and must be known at plan time.

`web_acl_arn` alone decides whether the WAF association exists only when the
ARN is known at plan time. When the web ACL is created in the same apply, also
set `associate_web_acl = true`; otherwise plan fails with `Invalid count
argument`.

### Egress

The security group allows TCP egress to `vpc_cidr` on `egress_port_range`
(default 1-65535), which covers `ip` and `instance` targets and their health
checks. Narrow `egress_port_range` when every target and health-check port is
known. `egress_security_groups` adds rules to target security groups outside
the VPC CIDR, such as peered VPCs. `lambda` targets need no egress rule.

### Naming

The load balancer is named `<name_prefix>-<environment>-alb`. Target groups are
named `<name_prefix>-<environment>-<key>`, cut to 27 characters, plus a
4-character hash suffix. The suffix covers the attributes that force
replacement (port, protocol, target type, protocol version), so changing one
produces a new name and `create_before_destroy` can create the replacement
before the listener releases the old group. Names over 32 characters are cut
the same way, so they stay deterministic.

### Logs

`access_logs` and `connection_logs` take an S3 bucket name, not an ARN. The
bucket must allow log delivery from the regional ELB account or the
`logdelivery.elasticloadbalancing.amazonaws.com` service principal, and must
use SSE-S3; ALB log delivery does not support SSE-KMS.

### Destroying

`enable_deletion_protection` defaults to `true`. Set it to `false` and apply
before running `terraform destroy`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |



## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.prefix_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | Default certificate for the HTTPS listener (ACM or IAM server certificate ARN). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to all named resources. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets for the load balancer, in at least two Availability Zones. Public subnets for an internet-facing ALB, private subnets when internal = true. | `list(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR of the VPC. The security group allows egress to it on egress\_port\_range, which covers ip and instance targets and their health checks. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the load balancer, its security group and its target groups live in. | `string` | n/a | yes |
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | Ship access logs to this S3 bucket. The bucket policy must allow the regional ELB log delivery principal, and the bucket must use SSE-S3 (SSE-KMS is not supported). Null = no access logs. | <pre>object({<br/>    bucket = string<br/>    prefix = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_additional_certificate_arns"></a> [additional\_certificate\_arns](#input\_additional\_certificate\_arns) | Extra certificates for the HTTPS listener (SNI), as label => certificate ARN. Labels are for\_each keys, so ARNs may be computed in the same apply. | `map(string)` | `{}` | no |
| <a name="input_associate_web_acl"></a> [associate\_web\_acl](#input\_associate\_web\_acl) | Whether to create the WAFv2 association. Null = infer from web\_acl\_arn != null, which only works when the ARN is known at plan time; set true when the web ACL is created in the same apply. | `bool` | `null` | no |
| <a name="input_connection_logs"></a> [connection\_logs](#input\_connection\_logs) | Ship connection logs (client TLS handshake details) to this S3 bucket. Same bucket requirements as access\_logs. Null = no connection logs. | <pre>object({<br/>    bucket = string<br/>    prefix = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_default_target_group_key"></a> [default\_target\_group\_key](#input\_default\_target\_group\_key) | Key of target\_groups that the HTTPS listener forwards to when no listener rule matches. Null = fixed 404 response. | `string` | `null` | no |
| <a name="input_desync_mitigation_mode"></a> [desync\_mitigation\_mode](#input\_desync\_mitigation\_mode) | How the ALB treats requests that may pose an HTTP desync risk: monitor, defensive, or strictest. | `string` | `"strictest"` | no |
| <a name="input_egress_port_range"></a> [egress\_port\_range](#input\_egress\_port\_range) | TCP port range the ALB may open to targets. The default covers any target port; narrow it when every target and health-check port is known. | <pre>object({<br/>    from_port = number<br/>    to_port   = number<br/>  })</pre> | <pre>{<br/>  "from_port": 1,<br/>  "to_port": 65535<br/>}</pre> | no |
| <a name="input_egress_security_groups"></a> [egress\_security\_groups](#input\_egress\_security\_groups) | Target security groups the ALB may reach, as label => security group ID (e.g. { eks\_nodes = module.eks.node\_security\_group\_id }). Added on top of the VPC CIDR egress rule. Labels are for\_each keys, so IDs may be computed in the same apply. | `map(string)` | `{}` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Block deletion of the load balancer through the AWS API. Set false before destroying. | `bool` | `true` | no |
| <a name="input_http_redirect"></a> [http\_redirect](#input\_http\_redirect) | Create an HTTP :80 listener that answers every request with a 301 redirect to HTTPS, and open port 80 on the security group. The HTTP listener never forwards. | `bool` | `true` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | Seconds a connection may stay idle before the ALB closes it. | `number` | `60` | no |
| <a name="input_ingress_cidr_blocks"></a> [ingress\_cidr\_blocks](#input\_ingress\_cidr\_blocks) | IPv4 CIDRs allowed to reach the listeners (443, and 80 when http\_redirect = true). Narrow this for internal load balancers. Values must be known at plan time. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_ingress_prefix_list_ids"></a> [ingress\_prefix\_list\_ids](#input\_ingress\_prefix\_list\_ids) | Managed prefix lists allowed to reach the listeners, as label => prefix list ID (e.g. { cloudfront = "pl-82a045eb" }). Labels are for\_each keys, so IDs may be computed in the same apply. | `map(string)` | `{}` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Create an internal load balancer (private IPs only). false = internet-facing. | `bool` | `false` | no |
| <a name="input_listener_rules"></a> [listener\_rules](#input\_listener\_rules) | Forward rules on the HTTPS listener, keyed by short name. Each rule needs at least one host\_header or path\_pattern value (at most 5 values in total) and forwards matching requests to target\_groups[target\_group\_key]. | <pre>map(object({<br/>    priority         = number<br/>    target_group_key = string<br/>    host_header      = optional(list(string), [])<br/>    path_pattern     = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_preserve_host_header"></a> [preserve\_host\_header](#input\_preserve\_host\_header) | Forward the client's Host header to targets unchanged instead of rewriting the port. | `bool` | `false` | no |
| <a name="input_ssl_policy"></a> [ssl\_policy](#input\_ssl\_policy) | Security policy for the HTTPS listener. Restricted to TLS 1.3 policies (ELBSecurityPolicy-TLS13-*). | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | Target groups keyed by short name (lowercase alphanumerics and hyphens).<br/>The AWS name is <name\_prefix>-<environment>-<key>, cut to 27 characters,<br/>plus a 4-hex suffix. target\_type = "ip" suits EKS (AWS Load Balancer<br/>Controller TargetGroupBinding) and ECS awsvpc tasks. For "lambda" targets,<br/>port / protocol / protocol\_version are ignored and the caller must grant<br/>elasticloadbalancing.amazonaws.com lambda:InvokeFunction. health\_check<br/>.protocol defaults to the group's protocol; health\_check.matcher defaults<br/>to "200-399" ("12" for GRPC). | <pre>map(object({<br/>    port                 = optional(number, 80)<br/>    protocol             = optional(string, "HTTP")<br/>    protocol_version     = optional(string, "HTTP1")<br/>    target_type          = optional(string, "ip")<br/>    deregistration_delay = optional(number, 30)<br/>    health_check = optional(object({<br/>      enabled             = optional(bool, true)<br/>      path                = optional(string, "/")<br/>      port                = optional(string, "traffic-port")<br/>      protocol            = optional(string)<br/>      matcher             = optional(string)<br/>      interval            = optional(number, 15)<br/>      timeout             = optional(number, 5)<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>    }), {})<br/>    stickiness = optional(object({<br/>      enabled         = optional(bool, true)<br/>      type            = optional(string, "lb_cookie")<br/>      cookie_duration = optional(number, 86400)<br/>      cookie_name     = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | WAFv2 web ACL (REGIONAL scope) to associate with the load balancer. Null = no association. When the ARN is computed in the same apply, also set associate\_web\_acl = true. | `string` | `null` | no |
| <a name="input_xff_header_processing_mode"></a> [xff\_header\_processing\_mode](#input\_xff\_header\_processing\_mode) | How the ALB handles the X-Forwarded-For header: append, preserve, or remove. | `string` | `"append"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_http_listener_arn"></a> [http\_listener\_arn](#output\_http\_listener\_arn) | HTTP redirect listener ARN. Null when http\_redirect = false. |
| <a name="output_https_listener_arn"></a> [https\_listener\_arn](#output\_https\_listener\_arn) | HTTPS listener ARN. Attach further listener rules here. |
| <a name="output_lb_arn"></a> [lb\_arn](#output\_lb\_arn) | Load balancer ARN. |
| <a name="output_lb_arn_suffix"></a> [lb\_arn\_suffix](#output\_lb\_arn\_suffix) | Load balancer ARN suffix, the LoadBalancer dimension for CloudWatch metrics. |
| <a name="output_lb_dns_name"></a> [lb\_dns\_name](#output\_lb\_dns\_name) | Load balancer DNS name (target of a Route 53 alias record). |
| <a name="output_lb_zone_id"></a> [lb\_zone\_id](#output\_lb\_zone\_id) | Route 53 hosted zone ID of the load balancer, for alias records. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group attached to the load balancer. Reference it from target security groups to admit ALB traffic. |
| <a name="output_target_group_arn_suffixes"></a> [target\_group\_arn\_suffixes](#output\_target\_group\_arn\_suffixes) | Map of target\_groups key => target group ARN suffix, the TargetGroup dimension for CloudWatch metrics. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Map of target\_groups key => target group ARN. |
<!-- END_TF_DOCS -->
