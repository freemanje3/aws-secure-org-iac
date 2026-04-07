#!/bin/bash
echo "Executing manual AWS deregulation for legacy administrator accounts to clear Terraform API errors..."

# Deregister logic dynamically grabs the Log Archive Account ID
LOG_ARCHIVE_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Log-Archive'].Id" --output text)

echo "Deregistering Log Archive ($LOG_ARCHIVE_ID) explicitly..."
aws guardduty disable-organization-admin-account --admin-account-id $LOG_ARCHIVE_ID || true
aws securityhub disable-organization-admin-account --admin-account-id $LOG_ARCHIVE_ID || true

# Just to be overly safe against Terraform state bloat, we ensure any trapped standalone resources are un-tracked.
terraform state rm aws_securityhub_organization_admin_account.org_admin || true
terraform state rm aws_guardduty_organization_admin_account.gd_admin || true
terraform state rm aws_securityhub_organization_configuration.org_config || true
terraform state rm aws_guardduty_organization_configuration.gd_org_config || true
