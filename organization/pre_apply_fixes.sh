#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

# 1. Manually resolve S3 BPA deletion loops (already successful but keeping for safety)
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. Get Log Archive ID to act as legacy Delegated Admin
LOG_ARCHIVE_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Log-Archive'].Id" --output text)

echo "Disabling GuardDuty & Security Hub configs INSIDE Log-Archive ($LOG_ARCHIVE_ID)..."
if [ -n "$LOG_ARCHIVE_ID" ] && [ "$LOG_ARCHIVE_ID" != "None" ]; then
    # Assume Role into Log Archive Account!
    CREDENTIALS=$(aws sts assume-role --role-arn "arn:aws:iam::$LOG_ARCHIVE_ID:role/OrganizationAccountAccessRole" --role-session-name "DeregisterAdmin" --query "Credentials" --output json)
    if [ -n "$CREDENTIALS" ]; then
        ASSUMED_AK=$(echo $CREDENTIALS | jq -r .AccessKeyId)
        ASSUMED_SK=$(echo $CREDENTIALS | jq -r .SecretAccessKey)
        ASSUMED_ST=$(echo $CREDENTIALS | jq -r .SessionToken)

        # Run GuardDuty cleanup AS Log-Archive Delegate
        AWS_ACCESS_KEY_ID=$ASSUMED_AK AWS_SECRET_ACCESS_KEY=$ASSUMED_SK AWS_SESSION_TOKEN=$ASSUMED_ST \
        bash -c '
            DETECTOR_ID=$(aws guardduty list-detectors --query "DetectorIds[0]" --output text || true)
            if [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ] && [ "$DETECTOR_ID" != "null" ]; then
                echo "Disabling AutoEnable on GuardDuty Org Configs..."
                aws guardduty update-organization-configuration --detector-id $DETECTOR_ID --auto-enable false || true
            fi

            echo "Disassociating all members from Security Hub..."
            # Security Hub needs member disassociation before deregistration!
            MEMBERS=$(aws securityhub list-members --query "Members[*].AccountId" --output text || true)
            for mem in $MEMBERS; do
                if [ -n "$mem" ] && [ "$mem" != "None" ] && [ "$mem" != "null" ]; then
                    echo "Disassociating $mem..."
                    aws securityhub disassociate-members --account-ids $mem || true
                    aws securityhub delete-members --account-ids $mem || true
                fi
            done
            aws securityhub update-organization-configuration --auto-enable false || true
        '
    fi
fi

# 3. GuardDuty Delegated Admins (Management Account)
echo "Getting active GuardDuty Admins..."
GD_ADMINS=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[*].AdminAccountId" --output text || echo "")
echo "GuardDuty Admins: $GD_ADMINS"

for admin in $GD_ADMINS; do
    if [ "$admin" != "None" ] && [ "$admin" != "null" ] && [ -n "$admin" ]; then
        echo "Deregistering GuardDuty Admin: $admin"
        aws guardduty disable-organization-admin-account --admin-account-id $admin
    fi
done

# 4. Security Hub Delegated Admins (Management Account)
echo "Getting active SecurityHub Admins..."
SH_ADMINS=$(aws securityhub list-organization-admin-accounts --query "AdminAccounts[*].AccountId" --output text || echo "")
echo "SecurityHub Admins: $SH_ADMINS"

for admin in $SH_ADMINS; do
    if [ "$admin" != "None" ] && [ "$admin" != "null" ] && [ -n "$admin" ]; then
        echo "Deregistering SecurityHub Admin: $admin"
        aws securityhub deregister-organization-admin-account --admin-account-id $admin
    fi
done

# 5. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true

echo "Sleeping 45s for complete AWS global API convergence..."
sleep 45
echo "Ready for main deployment!"
