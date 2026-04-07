# organization/accounts.tf

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

  depends_on = [time_sleep.wait_for_account_iam]
}

resource "aws_ebs_encryption_by_default" "log_archive" {
  provider = aws.log_archive
  enabled  = true

  depends_on = [time_sleep.wait_for_account_iam]
}

resource "aws_organizations_account" "security_tooling" {
  name                       = "Security-Tooling"
  email                      = "freemanje3.iac+security@gmail.com" # Update this alias if needed
  parent_id                  = aws_organizations_organizational_unit.security.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "time_sleep" "wait_for_security_account_iam" {
  depends_on      = [aws_organizations_account.security_tooling]
  create_duration = "2m"
}

resource "aws_s3_account_public_access_block" "security_tooling" {
  provider                = aws.security_tooling
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [time_sleep.wait_for_security_account_iam]
}

resource "aws_ebs_encryption_by_default" "security_tooling" {
  provider = aws.security_tooling
  enabled  = true

  depends_on = [time_sleep.wait_for_security_account_iam]
}