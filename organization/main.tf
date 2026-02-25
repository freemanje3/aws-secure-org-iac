# organization/main.tf

################################################################################
# 1. Terraform Configuration & Backend
################################################################################

terraform {
  backend "s3" {
    bucket         = "company-tf-state-079390753901"
    key            = "organization/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
  }
}

################################################################################
# 2. Provider Definitions & Data Sources
################################################################################

# Default Provider: Management Account
provider "aws" {
  region = "us-east-1"
}

# Aliased Provider: Log Archive Account
provider "aws" {
  alias  = "log_archive"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.log_archive.id}:role/OrganizationAccountAccessRole"
  }
}

# Required to dynamically fetch the Management Account ID for policies
data "aws_caller_identity" "current" {}

################################################################################
# 3. AWS Organizations & Organizational Units (OUs)
################################################################################

resource "aws_organizations_organization" "org" {
  feature_set = "ALL"
  
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY"
  ]

  aws_service_access_principals = [
    "sso.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com"
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.org.roots[0].id
}

################################################################################
# 4. Member Accounts & Baselines
################################################################################

resource "aws_organizations_account" "log_archive" {
  name                       = "Log-Archive"
  email                      = "freemanje3.iac+logs@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.security.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

# Add this right after the account resource (Approx line 77)
# Pauses Terraform execution for 2 minutes after an account is created
# to allow the OrganizationAccountAccessRole to propagate.
resource "time_sleep" "wait_for_account_iam" {
  depends_on      = [aws_organizations_account.log_archive]
  create_duration = "2m"
}

resource "aws_s3_account_public_access_block" "log_archive" {
  provider                = aws.log_archive
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  
  # Add this right before the closing brace (Approx line 89)
  # Forces Terraform to wait for the IAM role before trying to connect
  depends_on = [time_sleep.wait_for_account_iam] 
}

resource "aws_ebs_encryption_by_default" "log_archive" {
  provider = aws.log_archive
  enabled  = true
}

######################################################
# 5. Centralized KMS Resources (Log Archive Account)
################################################################################

resource "aws_kms_key" "central_log_key" {
  provider                = aws.log_archive
  description             = "Centralized KMS key for Organization-wide logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.central_log_key_policy.json
}

resource "aws_kms_alias" "central_log_key_alias" {
  provider      = aws.log_archive
  name          = "alias/central-logs-key"
  target_key_id = aws_kms_key.central_log_key.key_id
}

################################################################################
# 6. IAM Policy Documents (KMS)
################################################################################

data "aws_iam_policy_document" "central_log_key_policy" {
  provider = aws.log_archive

  # 1. Full access for the Log Archive account root
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_organizations_account.log_archive.id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # 2. Permission for CloudWatch Logs across the entire Organization
  statement {
    sid    = "AllowCloudWatchLogsAcrossOrg"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [aws_organizations_organization.org.id]
    }
  }

  # 3. Allow CloudTrail to encrypt logs (Properly nested inside the data block now)
  statement {
    sid    = "AllowCloudTrailToEncryptLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]
    
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
    }
  }
}

################################################################################
# 7. Organizational Guardrails (SCPs)
################################################################################

resource "aws_organizations_policy" "protect_central_logging" {
  name        = "ProtectCentralLoggingArchitecture"
  description = "Prevents tampering with centralized logs and encryption keys"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.scp_protect_logging.json
}

resource "aws_organizations_policy_attachment" "secure_root_attachment" {
  policy_id = aws_organizations_policy.protect_central_logging.id
  target_id = aws_organizations_organization.org.roots[0].id
}

data "aws_iam_policy_document" "scp_protect_logging" {
  
  statement {
    sid       = "PreventLogDeletion"
    effect    = "Deny"
    actions   = ["logs:DeleteLogGroup"]
    resources = ["*"]
    
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }

  statement {
    sid    = "PreventCentralKeyTampering"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:PutKeyPolicy"
    ]
    resources = [aws_kms_key.central_log_key.arn]
    
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }

  statement {
    sid       = "EnforceSecureTransportS3"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["*"]
    
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
} 

################################################################################
# 8. Detective Guardrails (AWS Config Organization Rules)
################################################################################

resource "aws_config_organization_managed_rule" "central_log_key_check" {
  name            = "require-central-log-key"
  rule_identifier = "CLOUDWATCH_LOG_GROUP_ENCRYPTED"
  description     = "Ensures all CloudWatch Log groups use the central Organization KMS key."

  input_parameters = jsonencode({
    kmsKeyArn = aws_kms_key.central_log_key.arn
  })

  depends_on = [aws_organizations_organization.org]
}

resource "aws_config_organization_conformance_pack" "nist_800_53" {
  name             = "NIST-800-53-Rev5-Operational-Best-Practices"
  template_body    = file("${path.module}/nist-800-53-rev-5.yaml")
  delivery_s3_bucket = aws_s3_bucket.org_conformance_pack_delivery.bucket
  depends_on = [aws_organizations_organization.org]
}

################################################################################
# 9. Conformance Pack Delivery Bucket (Log Archive Account)
################################################################################

resource "aws_s3_bucket" "org_conformance_pack_delivery" {
  provider      = aws.log_archive
  
  # AWS strictly requires the 'awsconfigconforms' prefix for this specific bucket
  bucket        = "awsconfigconforms-org-delivery-${aws_organizations_account.log_archive.id}"
  
  force_destroy = false 
}

resource "aws_s3_bucket_public_access_block" "conformance_pack_bpa" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.org_conformance_pack_delivery.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "conformance_pack_policy" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_conformance_pack_delivery.id
  policy   = data.aws_iam_policy_document.conformance_pack_bucket_policy.json
}

data "aws_iam_policy_document" "conformance_pack_bucket_policy" {
  provider = aws.log_archive

  statement {
    sid    = "AllowConfigAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.org_conformance_pack_delivery.arn]
  }

  statement {
    sid    = "AllowConfigWriteAccess"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.org_conformance_pack_delivery.arn}/AWSLogs/*"]
    
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    } # Properly closed condition
  } # Properly closed statement
} # Properly closed data block

resource "aws_s3_bucket_versioning" "conformance_pack" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_conformance_pack_delivery.id
  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# 10. General Storage CMK (Log Archive Account)
################################################################################

resource "aws_kms_key" "log_archive_storage_key" {
  provider                = aws.log_archive
  description             = "CMK for general storage (EBS, S3, RDS) in Log Archive Account"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.log_archive_storage_key_policy.json
}

resource "aws_kms_alias" "log_archive_storage_key_alias" {
  provider      = aws.log_archive
  name          = "alias/log-archive-storage-key"
  target_key_id = aws_kms_key.log_archive_storage_key.key_id
}

data "aws_iam_policy_document" "log_archive_storage_key_policy" {
  provider = aws.log_archive

  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_organizations_account.log_archive.id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_ebs_default_kms_key" "log_archive_default" {
  provider   = aws.log_archive
  key_arn    = aws_kms_key.log_archive_storage_key.arn
  depends_on = [aws_ebs_encryption_by_default.log_archive] 
}

################################################################################
# 11. Secure Networking & Gateway Endpoints (Log Archive Account)
################################################################################

resource "aws_vpc" "log_archive_vpc" {
  provider             = aws.log_archive
  cidr_block           = "10.1.0.0/16" 
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "log_archive_isolated_subnet" {
  provider   = aws.log_archive
  vpc_id     = aws_vpc.log_archive_vpc.id
  cidr_block = "10.1.1.0/24"
}

resource "aws_route_table" "log_archive_isolated_rt" {
  provider = aws.log_archive
  vpc_id   = aws_vpc.log_archive_vpc.id
}

resource "aws_route_table_association" "log_archive_isolated_rta" {
  provider       = aws.log_archive
  subnet_id      = aws_subnet.log_archive_isolated_subnet.id
  route_table_id = aws_route_table.log_archive_isolated_rt.id
}

resource "aws_vpc_endpoint" "log_archive_s3_gateway" {
  provider          = aws.log_archive
  vpc_id            = aws_vpc.log_archive_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.log_archive_isolated_rt.id]
}

resource "aws_vpc_endpoint" "log_archive_dynamodb_gateway" {
  provider          = aws.log_archive
  vpc_id            = aws_vpc.log_archive_vpc.id
  service_name      = "com.amazonaws.us-east-1.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.log_archive_isolated_rt.id]
}

################################################################################
# 12. Centralized CloudTrail S3 Vault (Log Archive Account)
################################################################################

resource "aws_s3_bucket" "org_cloudtrail_vault" {
  provider      = aws.log_archive
  bucket        = "org-cloudtrail-vault-${aws_organizations_account.log_archive.id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "org_cloudtrail_bpa" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.org_cloudtrail_vault.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "org_cloudtrail_policy" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_cloudtrail_vault.id
  policy   = data.aws_iam_policy_document.org_cloudtrail_vault_policy.json
}

data "aws_iam_policy_document" "org_cloudtrail_vault_policy" {
  provider = aws.log_archive

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.org_cloudtrail_vault.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.org_cloudtrail_vault.arn}/AWSLogs/${aws_organizations_organization.org.id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

################################################################################
# 13. Organization CloudTrail (Management Account)
################################################################################

resource "aws_cloudwatch_log_group" "org_cloudtrail_logs" {
  name              = "/aws/cloudtrail/organization-trail"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.central_log_key.arn
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "CloudTrailToCloudWatchLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch_policy" {
  name = "CloudTrailToCloudWatchLogsPolicy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.org_cloudtrail_logs.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "org_trail" {
  name                          = "organization-master-trail"
  s3_bucket_name                = aws_s3_bucket.org_cloudtrail_vault.id
  
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.central_log_key.arn

  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.org_cloudtrail_logs.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [
    aws_s3_bucket_policy.org_cloudtrail_policy,
    aws_organizations_organization.org
  ]
}

################################################################################
# 14. VPC Flow Logs & GuardDuty (Management Account)
################################################################################

# --- VPC Flow Logs ---
data "aws_vpc" "management_vpc" {
  cidr_block = "10.0.0.0/16" # Matches the VPC in bootstrap.tf
}

resource "aws_cloudwatch_log_group" "management_vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/management"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.central_log_key.arn
}

resource "aws_iam_role" "management_flow_logs_role" {
  name = "ManagementVPCFlowLogsRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "management_flow_logs_policy" {
  name = "ManagementVPCFlowLogsPolicy"
  role = aws_iam_role.management_flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.management_vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "management_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.management_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.management_vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = data.aws_vpc.management_vpc.id
}

# --- GuardDuty ---
resource "aws_guardduty_detector" "management_gd" {
  enable = true
}

resource "aws_cloudwatch_log_group" "management_guardduty_logs" {
  name              = "/aws/events/guardduty/management"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.central_log_key.arn
}

# Allows EventBridge to route GuardDuty findings to CloudWatch Logs
resource "aws_cloudwatch_log_resource_policy" "management_events_to_cwl" {
  policy_name = "ManagementEventBridgeToCWL"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.management_guardduty_logs.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "management_guardduty_rule" {
  name        = "management-guardduty-findings"
  description = "Capture GuardDuty Findings"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "management_guardduty_target" {
  rule = aws_cloudwatch_event_rule.management_guardduty_rule.name
  arn  = aws_cloudwatch_log_group.management_guardduty_logs.arn
}

################################################################################
# 15. VPC Flow Logs & GuardDuty (Log Archive Account)
################################################################################

# --- VPC Flow Logs ---
resource "aws_cloudwatch_log_group" "log_archive_vpc_flow_logs" {
  provider          = aws.log_archive
  name              = "/aws/vpc-flow-logs/log-archive"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.central_log_key.arn
}

resource "aws_iam_role" "log_archive_flow_logs_role" {
  provider = aws.log_archive
  name     = "LogArchiveVPCFlowLogsRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "log_archive_flow_logs_policy" {
  provider = aws.log_archive
  name     = "LogArchiveVPCFlowLogsPolicy"
  role     = aws_iam_role.log_archive_flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.log_archive_vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "log_archive_vpc_flow_log" {
  provider        = aws.log_archive
  iam_role_arn    = aws_iam_role.log_archive_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.log_archive_vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.log_archive_vpc.id
}

# --- GuardDuty ---
resource "aws_guardduty_detector" "log_archive_gd" {
  provider = aws.log_archive
  enable   = true
}

resource "aws_cloudwatch_log_group" "log_archive_guardduty_logs" {
  provider          = aws.log_archive
  name              = "/aws/events/guardduty/log-archive"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.central_log_key.arn
}

resource "aws_cloudwatch_log_resource_policy" "log_archive_events_to_cwl" {
  provider    = aws.log_archive
  policy_name = "LogArchiveEventBridgeToCWL"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.log_archive_guardduty_logs.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "log_archive_guardduty_rule" {
  provider    = aws.log_archive
  name        = "log-archive-guardduty-findings"
  description = "Capture GuardDuty Findings"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "log_archive_guardduty_target" {
  provider = aws.log_archive
  rule     = aws_cloudwatch_event_rule.log_archive_guardduty_rule.name
  arn      = aws_cloudwatch_log_group.log_archive_guardduty_logs.arn
}
