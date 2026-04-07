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
