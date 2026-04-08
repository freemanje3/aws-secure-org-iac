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

resource "aws_organizations_account" "routing" {
  name                       = "Routing"
  email                      = "freemanje3.iac+routing@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.infrastructure.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "shared_services" {
  name                       = "Shared-Services"
  email                      = "freemanje3.iac+sharedservices@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.infrastructure.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "development" {
  name                       = "Development"
  email                      = "freemanje3.iac+development@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.workloads.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "production" {
  name                       = "Production"
  email                      = "freemanje3.iac+production@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.workloads.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "data_ingestion" {
  name                       = "Data-Ingestion"
  email                      = "freemanje3.iac+dataingestion@gmail.com"
  parent_id                  = aws_organizations_organizational_unit.workloads.id
  iam_user_access_to_billing = "ALLOW"

  lifecycle {
    ignore_changes = [role_name]
  }
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

resource "time_sleep" "wait_for_account_iam" {
  depends_on = [
    aws_organizations_account.log_archive,
    aws_organizations_account.security_tooling,
    aws_organizations_account.routing,
    aws_organizations_account.shared_services,
    aws_organizations_account.development,
    aws_organizations_account.production,
    aws_organizations_account.data_ingestion
  ]
  create_duration = "3m"
}
