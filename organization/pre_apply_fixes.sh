#!/bin/bash
echo "=== Pre-Apply Ghost Cleanser Pipeline ==="

echo "Sweeping Organizations global root for ghost GuardDuty Admins..."
GD_ADMINS=$(aws organizations list-delegated-administrators --service-principal guardduty.amazonaws.com --query "DelegatedAdministrators[*].Id" --output text || echo "")
for admin in $GD_ADMINS; do
    if [ -n "$admin" ] && [ "$admin" != "None" ] && [ "$admin" != "null" ]; then
        echo "Found ghost GD Admin at Root: $admin. Force deregistering..."
        aws organizations deregister-delegated-administrator --account-id $admin --service-principal guardduty.amazonaws.com || true
    fi
done

echo "Sweeping Organizations global root for ghost Security Hub Admins..."
SH_ADMINS=$(aws organizations list-delegated-administrators --service-principal securityhub.amazonaws.com --query "DelegatedAdministrators[*].Id" --output text || echo "")
for admin in $SH_ADMINS; do
    if [ -n "$admin" ] && [ "$admin" != "None" ] && [ "$admin" != "null" ]; then
        echo "Found ghost SH Admin at Root: $admin. Force deregistering..."
        aws organizations deregister-delegated-administrator --account-id $admin --service-principal securityhub.amazonaws.com || true
    fi
done

# 1. Manually resolve S3 BPA deletion loops
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true
echo "Sleeping 20s for KMS replication..."
sleep 20
echo "=== Pre-Apply Ghost Cleanser Core Loops Finished ==="
