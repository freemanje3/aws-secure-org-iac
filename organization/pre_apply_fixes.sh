#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

# 1. Manually resolve S3 BPA deletion loops (already successful but keeping for safety)
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. Fix Terraform state for GuardDuty / Security Hub Admin if they were successfully deployed
echo "Attempting to import Security Tooling Admins to gracefully synchronize state..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)

if [ -n "$SECURITY_TOOLING_ID" ]; then
    terraform import aws_guardduty_organization_admin_account.gd_admin $SECURITY_TOOLING_ID || true
    terraform import aws_securityhub_organization_admin_account.org_admin $SECURITY_TOOLING_ID || true
fi

# 3. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true

echo "Sleeping 45s for complete AWS global API convergence..."
sleep 45
echo "Ready for main deployment!"
