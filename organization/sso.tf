# organization/sso.tf

################################################################################
# 16. AWS IAM Identity Center (SSO) Account Assignments
################################################################################

data "aws_ssoadmin_instances" "main" {}

data "aws_identitystore_user" "admin_user" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "james.freeman"
    }
  }
}

resource "aws_ssoadmin_permission_set" "admin_access" {
  name             = "OrganizationAdministrator"
  description      = "Full administrative access to manage centralized logging and security tools"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin_policy" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
}

resource "aws_ssoadmin_account_assignment" "log_archive_admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  target_id          = aws_organizations_account.log_archive.id
  target_type        = "AWS_ACCOUNT"
  principal_id       = data.aws_identitystore_user.admin_user.user_id
  principal_type     = "USER"
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
}

resource "aws_ssoadmin_account_assignment" "security_tooling_admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  target_id          = aws_organizations_account.security_tooling.id
  target_type        = "AWS_ACCOUNT"
  principal_id       = data.aws_identitystore_user.admin_user.user_id
  principal_type     = "USER"
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
}