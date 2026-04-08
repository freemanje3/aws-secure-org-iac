#!/bin/bash
set -e

# S3 BPA and EBS defaults 
terraform state mv aws_s3_account_public_access_block.log_archive 'module.log_archive_baseline.aws_s3_account_public_access_block.baseline' || true
terraform state mv aws_ebs_encryption_by_default.log_archive 'module.log_archive_baseline.aws_ebs_encryption_by_default.baseline' || true

# Config Recorders Management
terraform state mv aws_iam_role.config_role_management 'module.management_baseline.aws_iam_role.config_role' || true
terraform state mv aws_iam_role_policy_attachment.config_policy_attach_management 'module.management_baseline.aws_iam_role_policy_attachment.config_policy_attach' || true
terraform state mv aws_config_configuration_recorder.management 'module.management_baseline.aws_config_configuration_recorder.recorder' || true
terraform state mv aws_config_delivery_channel.management 'module.management_baseline.aws_config_delivery_channel.delivery' || true
terraform state mv aws_config_configuration_recorder_status.management 'module.management_baseline.aws_config_configuration_recorder_status.status' || true

# Config Recorders Log Archive
terraform state mv aws_iam_role.config_role_log_archive 'module.log_archive_baseline.aws_iam_role.config_role' || true
terraform state mv aws_iam_role_policy_attachment.config_policy_attach_log_archive 'module.log_archive_baseline.aws_iam_role_policy_attachment.config_policy_attach' || true
terraform state mv aws_config_configuration_recorder.log_archive 'module.log_archive_baseline.aws_config_configuration_recorder.recorder' || true
terraform state mv aws_config_delivery_channel.log_archive 'module.log_archive_baseline.aws_config_delivery_channel.delivery' || true
terraform state mv aws_config_configuration_recorder_status.log_archive 'module.log_archive_baseline.aws_config_configuration_recorder_status.status' || true

# Log Archive KMS Storage Keys
terraform state mv aws_kms_key.log_archive_storage_key 'module.log_archive_baseline.aws_kms_key.storage_key' || true
terraform state mv aws_kms_alias.log_archive_storage_key_alias 'module.log_archive_baseline.aws_kms_alias.storage_key_alias' || true
terraform state mv aws_ebs_default_kms_key.log_archive_default 'module.log_archive_baseline.aws_ebs_default_kms_key.default' || true

# Log Archive Secure Networking
terraform state mv aws_vpc.log_archive_vpc 'module.log_archive_baseline.aws_vpc.vpc' || true
terraform state mv aws_subnet.log_archive_isolated_subnet 'module.log_archive_baseline.aws_subnet.isolated_subnet' || true
terraform state mv aws_route_table.log_archive_isolated_rt 'module.log_archive_baseline.aws_route_table.isolated_rt' || true
terraform state mv aws_route_table_association.log_archive_isolated_rta 'module.log_archive_baseline.aws_route_table_association.isolated_rta' || true
terraform state mv aws_vpc_endpoint.log_archive_s3_gateway 'module.log_archive_baseline.aws_vpc_endpoint.s3_gateway' || true
terraform state mv aws_vpc_endpoint.log_archive_dynamodb_gateway 'module.log_archive_baseline.aws_vpc_endpoint.dynamodb_gateway' || true

# VPC Flow Logs and GuardDuty Management 
terraform state mv aws_cloudwatch_log_group.management_vpc_flow_logs 'module.management_baseline.aws_cloudwatch_log_group.vpc_flow_logs' || true
terraform state mv aws_iam_role.management_flow_logs_role 'module.management_baseline.aws_iam_role.flow_logs_role' || true
terraform state mv aws_iam_role_policy.management_flow_logs_policy 'module.management_baseline.aws_iam_role_policy.flow_logs_policy' || true
terraform state mv aws_flow_log.management_vpc_flow_log 'module.management_baseline.aws_flow_log.vpc_flow_log' || true

terraform state mv aws_guardduty_detector.management_gd 'module.management_baseline.aws_guardduty_detector.detector' || true
terraform state mv aws_cloudwatch_log_group.management_guardduty_logs 'module.management_baseline.aws_cloudwatch_log_group.guardduty_logs' || true
terraform state mv aws_cloudwatch_log_resource_policy.management_events_to_cwl 'module.management_baseline.aws_cloudwatch_log_resource_policy.events_to_cwl' || true
terraform state mv aws_cloudwatch_event_rule.management_guardduty_rule 'module.management_baseline.aws_cloudwatch_event_rule.guardduty_rule' || true
terraform state mv aws_cloudwatch_event_target.management_guardduty_target 'module.management_baseline.aws_cloudwatch_event_target.guardduty_target' || true

# VPC Flow Logs and GuardDuty Log Archive
terraform state mv aws_cloudwatch_log_group.log_archive_vpc_flow_logs 'module.log_archive_baseline.aws_cloudwatch_log_group.vpc_flow_logs' || true
terraform state mv aws_iam_role.log_archive_flow_logs_role 'module.log_archive_baseline.aws_iam_role.flow_logs_role' || true
terraform state mv aws_iam_role_policy.log_archive_flow_logs_policy 'module.log_archive_baseline.aws_iam_role_policy.flow_logs_policy' || true
terraform state mv aws_flow_log.log_archive_vpc_flow_log 'module.log_archive_baseline.aws_flow_log.vpc_flow_log' || true

terraform state mv aws_guardduty_detector.log_archive_gd 'module.log_archive_baseline.aws_guardduty_detector.detector' || true
terraform state mv aws_cloudwatch_log_group.log_archive_guardduty_logs 'module.log_archive_baseline.aws_cloudwatch_log_group.guardduty_logs' || true
terraform state mv aws_cloudwatch_log_resource_policy.log_archive_events_to_cwl 'module.log_archive_baseline.aws_cloudwatch_log_resource_policy.events_to_cwl' || true
terraform state mv aws_cloudwatch_event_rule.log_archive_guardduty_rule 'module.log_archive_baseline.aws_cloudwatch_event_rule.guardduty_rule' || true
terraform state mv aws_cloudwatch_event_target.log_archive_guardduty_target 'module.log_archive_baseline.aws_cloudwatch_event_target.guardduty_target' || true

# Security Tooling Defaults
terraform state mv aws_s3_account_public_access_block.security_tooling 'module.security_tooling_baseline.aws_s3_account_public_access_block.baseline' || true
terraform state mv aws_ebs_encryption_by_default.security_tooling 'module.security_tooling_baseline.aws_ebs_encryption_by_default.baseline' || true

# Orphan Legacy Conformance Pack S3 Bucket
terraform state rm aws_s3_bucket.org_conformance_pack_delivery || true
terraform state rm aws_s3_bucket_server_side_encryption_configuration.org_conformance_pack_encryption || true
terraform state rm aws_s3_bucket_public_access_block.conformance_pack_bpa || true
terraform state rm aws_s3_bucket_policy.conformance_pack_policy || true

# Heal broken state from synthetic Ghost Sweeper deregulation
terraform state rm aws_guardduty_organization_configuration.gd_org_config || true
terraform state rm aws_securityhub_organization_configuration.org_config || true
terraform state rm aws_securityhub_standards_subscription.nist_800_53_r5 || true

echo "Severing orphaned explicit Security Hub environments from Terraform tracking completely..."
terraform state rm 'module.management_baseline.aws_securityhub_account.securityhub' || true
terraform state rm 'module.log_archive_baseline.aws_securityhub_account.securityhub' || true
terraform state rm 'module.security_tooling_baseline.aws_securityhub_account.securityhub' || true

echo "Severing orphaned explicit Member GuardDuty environments from Terraform tracking completely..."
terraform state rm 'module.management_baseline.aws_guardduty_detector.detector[0]' || true
terraform state rm 'module.log_archive_baseline.aws_guardduty_detector.detector[0]' || true
terraform state rm 'module.management_baseline.aws_guardduty_detector.detector' || true
terraform state rm 'module.log_archive_baseline.aws_guardduty_detector.detector' || true
