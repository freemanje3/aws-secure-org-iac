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

    # FIX: AWS Services don't have an Org ID. We use ArnLike with the EncryptionContext 
    # to restrict the key usage to just your Management and Log Archive accounts.
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*",
        "arn:aws:logs:us-east-1:${aws_organizations_account.log_archive.id}:*",
        "arn:aws:logs:us-east-1:${aws_organizations_account.security_tooling.id}:*"
      ]
    }
  }

  # 3. Allow CloudTrail to encrypt logs
  statement {
    sid    = "AllowCloudTrailToEncryptLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey" # <-- FIX 1: CloudTrail must be able to describe the key
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
# 8. Detective Guardrails (AWS Config Organization Rules)
################################################################################

resource "aws_config_organization_managed_rule" "central_log_key_check" {
  name            = "require-central-log-key"
  rule_identifier = "CLOUDWATCH_LOG_GROUP_ENCRYPTED"
  description     = "Ensures all CloudWatch Log groups use the central Organization KMS key."

  input_parameters = jsonencode({
    KmsKeyId = aws_kms_key.central_log_key.arn
  })

  # Waits for recorders to exist before deploying the rule
  depends_on = [
    aws_organizations_organization.org,
    module.management_baseline,
    module.log_archive_baseline
  ]
}

################################################################################
# 9. Central Configuration Delivery Vault (Log Archive Account)
################################################################################

resource "aws_s3_bucket" "aws_config_delivery_vault" {
  provider = aws.log_archive

  bucket = "aws-config-delivery-vault-${aws_organizations_account.log_archive.id}"

  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws_config_vault_encryption" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aws_config_delivery_vault.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "aws_config_vault_bpa" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.aws_config_delivery_vault.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "aws_config_vault_policy" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.aws_config_delivery_vault.id
  policy   = data.aws_iam_policy_document.aws_config_vault_bucket_policy.json
}

data "aws_iam_policy_document" "aws_config_vault_bucket_policy" {
  provider = aws.log_archive

  # 1. Allow AWS Config Service Principal (Required for Delivery Channel pre-flight checks)
  statement {
    sid    = "AllowConfigServiceAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.aws_config_delivery_vault.arn]
  }

  statement {
    sid    = "AllowConfigServiceWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.aws_config_delivery_vault.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # 2. Allow Cross-Account Organization Access (Required for Member Delivery Channels)
  statement {
    sid    = "AllowOrganizationAclCheck"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.aws_config_delivery_vault.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [aws_organizations_organization.org.id]
    }
  }

  statement {
    sid    = "AllowOrganizationWriteAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.aws_config_delivery_vault.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [aws_organizations_organization.org.id]
    }
  }
}
################################################################################
################################################################################
# 12. Centralized CloudTrail S3 Vault (Log Archive Account)
################################################################################

resource "aws_s3_bucket" "org_cloudtrail_vault" {
  provider      = aws.log_archive
  bucket        = "org-cloudtrail-vault-${aws_organizations_account.log_archive.id}"
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "org_cloudtrail_vault_encryption" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.org_cloudtrail_vault.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.central_log_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
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
    actions = ["s3:PutObject"]
    resources = [
      # FIX 2: CloudTrail pre-flight checks require access to the Management Account prefix
      "${aws_s3_bucket.org_cloudtrail_vault.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
      "${aws_s3_bucket.org_cloudtrail_vault.arn}/AWSLogs/${aws_organizations_organization.org.id}/*"
    ]
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
  name           = "organization-master-trail"
  s3_bucket_name = aws_s3_bucket.org_cloudtrail_vault.id

  is_organization_trail      = true
  is_multi_region_trail      = true
  enable_log_file_validation = true
  kms_key_id                 = aws_kms_key.central_log_key.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.org_cloudtrail_logs.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [
    aws_s3_bucket_policy.org_cloudtrail_policy,
    aws_organizations_organization.org
  ]
}

################################################################################
################################################################################

################################################################################
# Account Baselines (Management, Log Archive, Security Tooling)
################################################################################

module "management_baseline" {
  source                     = "../modules/account-baseline"
  account_name_prefix        = "management"
  vpc_cidr                   = "10.0.0.0/16"
  isolated_subnet_cidr       = "10.0.1.0/24"
  central_config_bucket_name = aws_s3_bucket.aws_config_delivery_vault.bucket
  central_log_key_arn        = aws_kms_key.central_log_key.arn
}

module "log_archive_baseline" {
  source = "../modules/account-baseline"
  providers = {
    aws = aws.log_archive
  }
  account_name_prefix        = "log-archive"
  vpc_cidr                   = "10.1.0.0/16"
  isolated_subnet_cidr       = "10.1.1.0/24"
  central_config_bucket_name = aws_s3_bucket.aws_config_delivery_vault.bucket
  central_log_key_arn        = aws_kms_key.central_log_key.arn
}

module "security_tooling_baseline" {
  source = "../modules/account-baseline"
  providers = {
    aws = aws.security_tooling
  }
  account_name_prefix        = "security-tooling"
  vpc_cidr                   = "10.2.0.0/16"
  isolated_subnet_cidr       = "10.2.1.0/24"
  central_config_bucket_name = aws_s3_bucket.aws_config_delivery_vault.bucket
  central_log_key_arn        = aws_kms_key.central_log_key.arn
}

################################################################################
# 16. GuardDuty & Security Hub (Organization-Wide)
################################################################################

# --- GuardDuty ---

resource "aws_guardduty_organization_admin_account" "gd_admin" {
  admin_account_id = aws_organizations_account.security_tooling.id
}

resource "aws_guardduty_organization_configuration" "gd_org_config" {
  provider                         = aws.security_tooling
  auto_enable_organization_members = "ALL"
  detector_id                      = module.security_tooling_baseline.detector_id

  depends_on = [aws_guardduty_organization_admin_account.gd_admin]
}

# --- Security Hub ---

resource "aws_securityhub_account" "management" {}

resource "aws_securityhub_organization_admin_account" "org_admin" {
  depends_on       = [aws_securityhub_account.management]
  admin_account_id = aws_organizations_account.security_tooling.id
}

resource "aws_securityhub_organization_configuration" "org_config" {
  provider              = aws.security_tooling
  auto_enable           = true
  auto_enable_standards = "NONE"

  depends_on = [aws_securityhub_organization_admin_account.org_admin]
}

resource "aws_securityhub_standards_subscription" "nist_800_53_r5" {
  provider      = aws.security_tooling
  standards_arn = "arn:aws:securityhub:us-east-1::standards/nist-800-53/v/5.0.0"

  depends_on = [aws_securityhub_organization_configuration.org_config]
}
