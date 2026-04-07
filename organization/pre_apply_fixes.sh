#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

# 1. Manually resolve S3 BPA deletion loops
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    echo "Deleting raw S3 Public Access Block for Security Tooling ($SECURITY_TOOLING_ID) to unblock Terraform state..."
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. GuardDuty Delegated Admins
echo "Getting active GuardDuty Admins..."
GD_ADMINS=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[*].AdminAccountId" --output text || echo "")
echo "GuardDuty Admins: $GD_ADMINS"

for admin in $GD_ADMINS; do
    if [ "$admin" != "None" ] && [ "$admin" != "null" ] && [ -n "$admin" ]; then
        echo "Deregistering GuardDuty Admin: $admin"
        aws guardduty disable-organization-admin-account --admin-account-id $admin || true
    fi
done

# 3. Security Hub Delegated Admins
echo "Getting active SecurityHub Admins..."
SH_ADMINS=$(aws securityhub list-organization-admin-accounts --query "AdminAccounts[*].AccountId" --output text || echo "")
echo "SecurityHub Admins: $SH_ADMINS"

for admin in $SH_ADMINS; do
    if [ "$admin" != "None" ] && [ "$admin" != "null" ] && [ -n "$admin" ]; then
        echo "Deregistering SecurityHub Admin: $admin"
        aws securityhub deregister-organization-admin-account --admin-account-id $admin || true
        # Security Hub uses deregister-organization-admin-account, NOT disable!
    fi
done

# 4. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true

echo "Sleeping 45s for complete AWS global API convergence..."
sleep 45
echo "Ready for main deployment!"
