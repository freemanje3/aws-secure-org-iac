#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

# 1. Manually resolve S3 BPA deletion loops
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. Get Log Archive ID to sweep orphaned internal configurations
LOG_ARCHIVE_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Log-Archive'].Id" --output text)

echo "Disabling GuardDuty & Security Hub configs INSIDE Log-Archive ($LOG_ARCHIVE_ID)..."
if [ -n "$LOG_ARCHIVE_ID" ] && [ "$LOG_ARCHIVE_ID" != "None" ]; then
    CREDENTIALS=$(aws sts assume-role --role-arn "arn:aws:iam::$LOG_ARCHIVE_ID:role/OrganizationAccountAccessRole" --role-session-name "SweepConfigs" --query "Credentials" --output json || echo "")
    if [ -n "$CREDENTIALS" ]; then
        ASSUMED_AK=$(echo $CREDENTIALS | jq -r .AccessKeyId)
        ASSUMED_SK=$(echo $CREDENTIALS | jq -r .SecretAccessKey)
        ASSUMED_ST=$(echo $CREDENTIALS | jq -r .SessionToken)

        AWS_ACCESS_KEY_ID=$ASSUMED_AK AWS_SECRET_ACCESS_KEY=$ASSUMED_SK AWS_SESSION_TOKEN=$ASSUMED_ST \
        bash -c '
            DETECTOR_ID=$(aws guardduty list-detectors --query "DetectorIds[0]" --output text || true)
            if [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ] && [ "$DETECTOR_ID" != "null" ]; then
                echo "Disabling AutoEnable on GuardDuty Org Configs..."
                aws guardduty update-organization-configuration --detector-id $DETECTOR_ID --auto-enable false || true
            fi
            echo "Disassociating all members from Security Hub..."
            MEMBERS=$(aws securityhub list-members --query "Members[*].AccountId" --output text || true)
            for mem in $MEMBERS; do
                if [ -n "$mem" ] && [ "$mem" != "None" ] && [ "$mem" != "null" ]; then
                    aws securityhub disassociate-members --account-ids $mem || true
                    aws securityhub delete-members --account-ids $mem || true
                fi
            done
            aws securityhub update-organization-configuration --auto-enable false || true
        '
    fi
fi

# 3. Dynamically Import Currently Active Admins
echo "Fetching actively registered GuardDuty Admin..."
GD_CURRENT_ADMIN=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[0].AdminAccountId" --output text || echo "")
if [ "$GD_CURRENT_ADMIN" != "None" ] && [ -n "$GD_CURRENT_ADMIN" ] && [ "$GD_CURRENT_ADMIN" != "null" ]; then
    echo "Importing GuardDuty Admin: $GD_CURRENT_ADMIN"
    terraform import aws_guardduty_organization_admin_account.gd_admin $GD_CURRENT_ADMIN || true
fi

echo "Fetching actively registered SecurityHub Admin..."
SH_CURRENT_ADMIN=$(aws securityhub list-organization-admin-accounts --query "AdminAccounts[0].AccountId" --output text || echo "")
if [ "$SH_CURRENT_ADMIN" != "None" ] && [ -n "$SH_CURRENT_ADMIN" ] && [ "$SH_CURRENT_ADMIN" != "null" ]; then
    echo "Importing SecurityHub Admin: $SH_CURRENT_ADMIN"
    terraform import aws_securityhub_organization_admin_account.org_admin $SH_CURRENT_ADMIN || true
fi

# 4. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true

echo "Sleeping 45s for complete AWS global API convergence..."
sleep 45
echo "Ready for main deployment!"
