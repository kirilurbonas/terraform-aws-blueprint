# aurora

Encrypted Aurora cluster for PostgreSQL or MySQL with an RDS-managed master
password, module-owned networking, and optional Serverless v2 capacity and
reader autoscaling.

## Features

- `aurora-postgresql` and `aurora-mysql`; engine-aware port (5432 / 3306) and
  cluster parameter group family
- Storage encryption always on; optional customer-managed KMS key for storage,
  Performance Insights, and the master user secret
- Master password generated and rotated by RDS (`manage_master_user_password`);
  it never enters Terraform state
- IAM database authentication and deletion protection on by default
- Backups with configurable retention (default 14 days); production
  environments take a deterministically named final snapshot
- Explicit CloudWatch log groups for every exported log type, created before
  the cluster, with configurable retention and optional KMS encryption
- Cluster instances declared as a map (default two), never publicly
  accessible, with Performance Insights and Enhanced Monitoring on by default
- Optional Aurora Serverless v2 scaling, I/O-Optimized storage, Data API,
  backtracking (MySQL), and advanced Database Insights
- Optional Application Auto Scaling of Aurora Replicas on reader CPU
- Optional cluster-level CloudWatch alarms for CPU, freeable memory,
  connections, and replica lag
- Ingress restricted to caller-provided CIDR blocks and/or security groups

## Usage

```hcl
module "aurora" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/aurora?ref=v1.0.0"

  name_prefix = "platform"
  environment = "prod"
  project     = "blueprint"

  engine         = "aurora-postgresql"
  engine_version = "16.4"
  instance_class = "db.r6g.large"

  database_name = "appdb"
  kms_key_arn   = module.kms.key_arn

  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnet_ids
  allowed_security_groups = { eks_nodes = module.eks.node_security_group_id }
}
```

Applications connect to `cluster_endpoint` for writes and `reader_endpoint`
for reads. Credentials are read from the secret at `master_user_secret_arn`,
or, with IAM authentication, by granting `rds-db:connect` on
`cluster_resource_id`.

### Why a separate module from `rds`

Aurora uses a different resource model from single-instance RDS: storage and
replication belong to the cluster (`aws_rds_cluster`), instances
(`aws_rds_cluster_instance`) are compute only, failover is driven by
promotion tiers rather than a Multi-AZ standby, readers share one reader
endpoint, and parameters live in a cluster parameter group. Allocated storage,
storage autoscaling, Multi-AZ, and `replicate_source_db` replicas from the
`rds` module have no Aurora equivalent, while Serverless v2, backtracking,
reader autoscaling, and the Data API do not exist for RDS instances. Folding
both into one module would leave most inputs valid for only one engine family.

### Instances

`instances` is a map keyed by a short name that becomes the identifier suffix
(`<name_prefix>-<environment>-<engine>-<key>`). Aurora chooses the writer at
creation; `promotion_tier` (0-15, lower first) sets the failover order.

```hcl
module "aurora" {
  # ...
  instances = {
    a = { promotion_tier = 0 }
    b = { promotion_tier = 1 }
    c = { instance_class = "db.r6g.xlarge", promotion_tier = 2 }
  }
}
```

### Aurora Serverless v2

Set `instance_class = "db.serverless"` (globally or per instance) and give the
cluster a capacity range in ACUs. Provisioned and serverless instances can be
mixed in one cluster.

```hcl
module "aurora" {
  # ...
  instance_class = "db.serverless"
  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 16
  }
}
```

Capacities are validated to 0-256 in 0.5 ACU steps with `min_capacity <=
max_capacity`. `min_capacity = 0` enables automatic pause on engine versions
that support it; `seconds_until_auto_pause` then sets the idle period. Planning
a `db.serverless` instance without a scaling configuration fails.

### RDS-managed master password

The module always sets `manage_master_user_password = true`. RDS generates the
password, stores it in a Secrets Manager secret it owns, and rotates it; there
is no `random_password` and no plaintext in state. The secret is encrypted with
`master_user_secret_kms_key_id`, falling back to `kms_key_arn`, then to the
AWS-managed `aws/secretsmanager` key. It contains only `username` and
`password`; read host, port, and database name from the module outputs.

### Reader autoscaling

`reader_autoscaling` registers the cluster with Application Auto Scaling and
adds a target-tracking policy on `RDSReaderAverageCPUUtilization`:

```hcl
module "aurora" {
  # ...
  reader_autoscaling = {
    min_capacity = 1
    max_capacity = 4
    target_cpu   = 70
  }
}
```

Replicas added by autoscaling are created by AWS, not Terraform. They are not
in state and take the writer's instance class. The bounds count only these
autoscaled replicas, not the instances declared in `instances`. Before
destroying the cluster, scale them in (set `min_capacity = 0` and wait) or
delete them; a cluster that still has instances cannot be deleted.

### Security group ingress

`allowed_security_groups` is a map of static caller-chosen label to security
group ID. The labels are the `for_each` keys, so the IDs may be computed in the
same apply (for example `module.eks.node_security_group_id` on a first
deploy). There is no list form; a list of computed IDs used as a `for_each`
set fails with `Invalid for_each argument` (see the `rds` module README).
`allowed_cidr_blocks` takes literal CIDRs.

### Logs, parameters, and backtracking

`enabled_cloudwatch_logs_exports` defaults to `["postgresql"]` for
aurora-postgresql and `["audit", "error", "slowquery"]` for aurora-mysql. A log
group named `/aws/rds/cluster/<identifier>/<type>` is created for each before
the cluster, so RDS never creates one without retention.

The cluster parameter group is seeded with slow-query and connection logging,
and for aurora-mysql with `server_audit_logging`, which the `audit` export
requires. Entries in `cluster_parameters` with the same name replace a
default. The family is derived from `engine` and `engine_version`
(`aurora-postgresql16`, `aurora-mysql8.0`); set `parameter_group_family` to
override it.

`backtrack_window` (seconds, up to 72 hours) is accepted for aurora-mysql
only; a non-zero value on aurora-postgresql fails at plan.

### CloudWatch alarms

`create_cloudwatch_alarms = true` creates four alarms on the cluster
(`DBClusterIdentifier` dimension), named
`<name_prefix>-<environment>-<engine>-<metric>`:

| Key | Metric | Statistic | Fires when | Default |
|-----|--------|-----------|------------|---------|
| `cpu-utilization` | `CPUUtilization` | Average | above | 80 % |
| `freeable-memory` | `FreeableMemory` | Average | below | 256 MiB |
| `database-connections` | `DatabaseConnections` | Average | above | 100 |
| `replica-lag` | `AuroraReplicaLagMaximum` | Maximum | above | 1000 ms |

Each alarm evaluates over `period_seconds` (default 300) for
`evaluation_periods` (default 3). Override any subset through
`cloudwatch_alarm_thresholds`. Alarm ARNs are exposed at
`cloudwatch_alarm_arns`.

### Notes

- `ca_cert_identifier` is applied to each cluster instance. The cluster-level
  `ca_certificate_identifier` argument only applies to Multi-AZ DB clusters,
  not Aurora, and is not exposed.
- `database_insights_mode = "advanced"` enables cluster-level Performance
  Insights and requires `performance_insights_retention_days >= 465`.
- `copy_tags_to_snapshot` is always on and `publicly_accessible` is always
  false.

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix on resource names. |
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `engine` | `string` | — | yes | `aurora-postgresql` or `aurora-mysql`. |
| `engine_version` | `string` | — | yes | Aurora engine version. |
| `instance_class` | `string` | — | yes | Default instance class, e.g. `db.r6g.large` or `db.serverless`. |
| `parameter_group_family` | `string` | derived | no | Override the cluster parameter group family. |
| `cluster_parameters` | `list(object)` | `[]` | no | Cluster parameters; same-name entries replace defaults. |
| `kms_key_arn` | `string` | `null` | no | CMK for storage, Performance Insights, and the master secret. |
| `storage_type` | `string` | `null` | no | `aurora` or `aurora-iopt1`. |
| `database_name` | `string` | — | yes | Initial database name. |
| `master_username` | `string` | `"dbadmin"` | no | Master user. |
| `master_user_secret_kms_key_id` | `string` | `null` | no | KMS key for the RDS-managed secret; falls back to `kms_key_arn`. |
| `iam_database_authentication_enabled` | `bool` | `true` | no | IAM DB auth. |
| `enable_http_endpoint` | `bool` | `false` | no | RDS Data API. |
| `vpc_id` | `string` | — | yes | VPC for the SG. |
| `subnet_ids` | `list(string)` | — | yes | Private subnets (≥ 2 AZs). |
| `allowed_cidr_blocks` | `list(string)` | `[]` | no | CIDR ingress. |
| `allowed_security_groups` | `map(string)` | `{}` | no | SG ingress as label → SG ID. |
| `instances` | `map(object)` | `{ one = {}, two = {} }` | no | Cluster instances; optional `instance_class`, `promotion_tier`, `availability_zone`. |
| `serverlessv2_scaling_configuration` | `object` | `null` | no | Serverless v2 ACU range. |
| `reader_autoscaling` | `object` | `null` | no | Replica autoscaling on reader CPU. |
| `backup_retention_days` | `number` | `14` | no | Days of automated backups (1-35). |
| `backup_window` | `string` | `"03:00-04:00"` | no | UTC. |
| `maintenance_window` | `string` | `"Sun:04:30-Sun:05:30"` | no | UTC. |
| `backtrack_window` | `number` | `0` | no | Backtrack seconds; aurora-mysql only. |
| `deletion_protection` | `bool` | `true` | no | Block destroy via AWS API. |
| `auto_minor_version_upgrade` | `bool` | `true` | no | Auto-apply minor upgrades. |
| `apply_immediately` | `bool` | `null` | no | Override when changes apply; `null` = immediately outside prod, maintenance window in prod. |
| `ca_cert_identifier` | `string` | `null` | no | Instance server certificate CA. |
| `performance_insights_enabled` | `bool` | `true` | no | Performance Insights on instances. |
| `performance_insights_retention_days` | `number` | `7` | no | PI retention. |
| `database_insights_mode` | `string` | `null` | no | `standard` or `advanced`. |
| `monitoring_interval` | `number` | `60` | no | Enhanced Monitoring seconds. |
| `enabled_cloudwatch_logs_exports` | `list(string)` | engine default | no | Exported log types. |
| `cloudwatch_log_retention_days` | `number` | `90` | no | Retention for exported log groups. |
| `cloudwatch_log_kms_key_arn` | `string` | `null` | no | Optional KMS key for exported log groups. |
| `create_cloudwatch_alarms` | `bool` | `false` | no | Create CPU / memory / connection / replica lag alarms. |
| `cloudwatch_alarm_thresholds` | `object` | see above | no | Alarm thresholds and evaluation window. |
| `alarm_actions` | `list(string)` | `[]` | no | SNS topic ARNs for ALARM transitions. |
| `ok_actions` | `list(string)` | `[]` | no | SNS topic ARNs for OK transitions. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_arn` | Cluster ARN. |
| `cluster_id` | Cluster ID. |
| `cluster_identifier` | Cluster identifier. |
| `cluster_resource_id` | Cluster resource ID (IAM auth policies). |
| `cluster_endpoint` | Writer endpoint. |
| `reader_endpoint` | Reader endpoint. |
| `port` | Listener port. |
| `database_name` | Initial database name. |
| `master_username` | Master username. |
| `master_user_secret_arn` | RDS-managed master secret ARN. |
| `security_group_id` | Cluster SG ID. |
| `db_subnet_group_name` | DB subnet group name. |
| `cluster_parameter_group_name` | Cluster parameter group name. |
| `instance_identifiers` | Map of instance key → identifier. |
| `instance_endpoints` | Map of instance key → endpoint. |
| `cloudwatch_log_group_names` | Map of log type → log group name. |
| `cloudwatch_alarm_arns` | Map of alarm key → ARN. |

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
| [aws_appautoscaling_policy.readers_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.readers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.exports](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_parameter_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.monitoring_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Initial database created in the cluster. | `string` | n/a | yes |
| <a name="input_engine"></a> [engine](#input\_engine) | Aurora engine. Supported: aurora-postgresql, aurora-mysql. | `string` | n/a | yes |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora engine version (e.g. "16.4" for aurora-postgresql, "8.0.mysql\_aurora.3.08.0" for aurora-mysql). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Default instance class for cluster instances (e.g. db.r6g.large, or db.serverless for Aurora Serverless v2). Overridable per instance. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to all named resources. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the DB subnet group. Should be private. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC where the cluster security group is created. | `string` | n/a | yes |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | SNS topic ARNs notified when an alarm enters the ALARM state. | `list(string)` | `[]` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | CIDR blocks allowed to reach the DB port. Must be literal values known at plan time. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_groups"></a> [allowed\_security\_groups](#input\_allowed\_security\_groups) | Security groups allowed to reach the DB port, as a map of static caller-chosen label -> SG ID. Labels must be known at plan time; values need not be (e.g. module.eks.node\_security\_group\_id). | `map(string)` | `{}` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications immediately instead of in the next maintenance window. Null keeps the module's environment-based behaviour: immediately outside prod, maintenance window in prod. | `bool` | `null` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Allow RDS to apply minor engine upgrades to cluster instances automatically during the maintenance window. | `bool` | `true` | no |
| <a name="input_backtrack_window"></a> [backtrack\_window](#input\_backtrack\_window) | Target backtrack window in seconds (aurora-mysql only). 0 disables; maximum 259200 (72 hours). | `number` | `0` | no |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | Days to keep automated backups. | `number` | `14` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | Preferred backup window in UTC (e.g. "03:00-04:00"). | `string` | `"03:00-04:00"` | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | Certificate authority for the instances' server certificate (e.g. rds-ca-rsa2048-g1, rds-ca-rsa4096-g1, rds-ca-ecc384-g1). Null leaves the RDS regional default. | `string` | `null` | no |
| <a name="input_cloudwatch_alarm_thresholds"></a> [cloudwatch\_alarm\_thresholds](#input\_cloudwatch\_alarm\_thresholds) | Thresholds and evaluation window for the alarms created by create\_cloudwatch\_alarms. Omitted attributes take their defaults. database\_connections should be sized to the instance class's max\_connections. | <pre>object({<br/>    cpu_utilization_percent = optional(number, 80)<br/>    freeable_memory_mb      = optional(number, 256)<br/>    database_connections    = optional(number, 100)<br/>    replica_lag_ms          = optional(number, 1000)<br/>    period_seconds          = optional(number, 300)<br/>    evaluation_periods      = optional(number, 3)<br/>  })</pre> | `{}` | no |
| <a name="input_cloudwatch_log_kms_key_arn"></a> [cloudwatch\_log\_kms\_key\_arn](#input\_cloudwatch\_log\_kms\_key\_arn) | Optional KMS key ARN for encrypting the CloudWatch log groups that receive exported DB logs. | `string` | `null` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | Retention in days for the CloudWatch log groups that receive exported DB logs. | `number` | `90` | no |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster\_parameters) | Cluster parameters merged on top of the engine defaults; an entry with the same name as a default replaces it. Static parameters need apply\_method = "pending-reboot". | <pre>list(object({<br/>    name         = string<br/>    value        = string<br/>    apply_method = optional(string, "immediate")<br/>  }))</pre> | `[]` | no |
| <a name="input_create_cloudwatch_alarms"></a> [create\_cloudwatch\_alarms](#input\_create\_cloudwatch\_alarms) | Create cluster-level CloudWatch metric alarms for CPUUtilization, FreeableMemory, DatabaseConnections, and AuroraReplicaLagMaximum. | `bool` | `false` | no |
| <a name="input_database_insights_mode"></a> [database\_insights\_mode](#input\_database\_insights\_mode) | CloudWatch Database Insights mode for the cluster: standard or advanced. Advanced requires performance\_insights\_retention\_days >= 465. Null leaves the AWS default (standard). | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block the cluster from being deleted without first removing this flag. | `bool` | `true` | no |
| <a name="input_enable_http_endpoint"></a> [enable\_http\_endpoint](#input\_enable\_http\_endpoint) | Enable the RDS Data API (HTTP endpoint) on the cluster. | `bool` | `false` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | Log types exported to CloudWatch Logs. Null uses the engine default: ["postgresql"] for aurora-postgresql, ["audit", "error", "slowquery"] for aurora-mysql. A module-managed log group is created for each. | `list(string)` | `null` | no |
| <a name="input_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#input\_iam\_database\_authentication\_enabled) | Enable IAM database authentication on the cluster. | `bool` | `true` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Cluster instances keyed by short name (used as the identifier suffix). instance\_class defaults to var.instance\_class. Aurora picks the writer; promotion\_tier (0-15, lower first) sets failover order. Instances are never publicly accessible. | <pre>map(object({<br/>    instance_class    = optional(string)<br/>    promotion_tier    = optional(number)<br/>    availability_zone = optional(string)<br/>  }))</pre> | <pre>{<br/>  "one": {},<br/>  "two": {}<br/>}</pre> | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer-managed KMS key ARN for cluster storage, Performance Insights, and (unless master\_user\_secret\_kms\_key\_id is set) the master user secret. Null = AWS-managed keys. Storage encryption itself is always on. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Preferred maintenance window in UTC (e.g. "Sun:04:30-Sun:05:30"). | `string` | `"Sun:04:30-Sun:05:30"` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | KMS key (ARN, key ID, or alias) for the RDS-managed master user secret. Falls back to kms\_key\_arn, then to the AWS-managed aws/secretsmanager key. | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master DB username. The password is always generated and rotated by RDS in a Secrets Manager secret. | `string` | `"dbadmin"` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring\_interval) | Enhanced Monitoring interval in seconds for cluster instances. 0 disables. Valid: 0, 1, 5, 10, 15, 30, 60. | `number` | `60` | no |
| <a name="input_ok_actions"></a> [ok\_actions](#input\_ok\_actions) | SNS topic ARNs notified when an alarm returns to the OK state. | `list(string)` | `[]` | no |
| <a name="input_parameter_group_family"></a> [parameter\_group\_family](#input\_parameter\_group\_family) | Cluster parameter group family (e.g. aurora-postgresql16, aurora-mysql8.0). Derived from engine/version when null. | `string` | `null` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Enable Performance Insights on every cluster instance. | `bool` | `true` | no |
| <a name="input_performance_insights_retention_days"></a> [performance\_insights\_retention\_days](#input\_performance\_insights\_retention\_days) | Performance Insights retention in days. 7 is free; longer values (multiples of 31, or 731) are billed. database\_insights\_mode = "advanced" requires at least 465. | `number` | `7` | no |
| <a name="input_reader_autoscaling"></a> [reader\_autoscaling](#input\_reader\_autoscaling) | Application Auto Scaling of Aurora Replicas on average reader CPU. min\_capacity/max\_capacity bound the autoscaled replica count (0-15). Null disables. | <pre>object({<br/>    min_capacity       = number<br/>    max_capacity       = number<br/>    target_cpu         = optional(number, 70)<br/>    scale_in_cooldown  = optional(number, 300)<br/>    scale_out_cooldown = optional(number, 300)<br/>  })</pre> | `null` | no |
| <a name="input_serverlessv2_scaling_configuration"></a> [serverlessv2\_scaling\_configuration](#input\_serverlessv2\_scaling\_configuration) | Aurora Serverless v2 capacity range in ACUs. Required when any instance uses db.serverless. min\_capacity = 0 enables auto-pause (engine-version dependent); seconds\_until\_auto\_pause (300-86400) only applies then. | <pre>object({<br/>    min_capacity             = number<br/>    max_capacity             = number<br/>    seconds_until_auto_pause = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Cluster storage configuration: aurora (Standard) or aurora-iopt1 (I/O-Optimized). Null leaves the AWS default (Standard). | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudwatch_alarm_arns"></a> [cloudwatch\_alarm\_arns](#output\_cloudwatch\_alarm\_arns) | Map of alarm key (cpu-utilization, freeable-memory, database-connections, replica-lag) -> CloudWatch alarm ARN. Empty unless create\_cloudwatch\_alarms = true. |
| <a name="output_cloudwatch_log_group_names"></a> [cloudwatch\_log\_group\_names](#output\_cloudwatch\_log\_group\_names) | Map of exported log type -> CloudWatch log group name. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | Aurora cluster ARN. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Writer endpoint hostname. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Aurora cluster ID (same as the cluster identifier). |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Aurora cluster identifier. |
| <a name="output_cluster_parameter_group_name"></a> [cluster\_parameter\_group\_name](#output\_cluster\_parameter\_group\_name) | Name of the cluster parameter group. |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | Region-unique, immutable cluster resource ID. Used in IAM database authentication policies (rds-db:connect). |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Initial database name. |
| <a name="output_db_subnet_group_name"></a> [db\_subnet\_group\_name](#output\_db\_subnet\_group\_name) | Name of the DB subnet group. |
| <a name="output_instance_endpoints"></a> [instance\_endpoints](#output\_instance\_endpoints) | Map of instance key -> instance endpoint hostname. Prefer cluster\_endpoint / reader\_endpoint for application traffic. |
| <a name="output_instance_identifiers"></a> [instance\_identifiers](#output\_instance\_identifiers) | Map of instance key -> cluster instance identifier. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the RDS-managed Secrets Manager secret holding the master credentials (username and password). |
| <a name="output_master_username"></a> [master\_username](#output\_master\_username) | Master username. |
| <a name="output_port"></a> [port](#output\_port) | Port the cluster is listening on. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Load-balanced reader endpoint hostname. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID guarding the cluster. |
<!-- END_TF_DOCS -->
