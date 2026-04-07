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

# 3. Aggressively Deregister Admins and Poll AWS API for Propagation Convergence
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)

echo "Deregistering GuardDuty Admins and waiting for propagation..."
while true; do
    GD_CHECK=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[0].AdminAccountId" --output text || echo "None")
    
    if [ "$GD_CHECK" == "None" ] || [ -z "$GD_CHECK" ] || [ "$GD_CHECK" == "null" ]; then
        echo "[√] SUCCESS: GuardDuty Admin cache is cleared globally."
        break
    elif [ "$GD_CHECK" == "$SECURITY_TOOLING_ID" ]; then
        echo "[√] SUCCESS: Security-Tooling is perfectly registered in GuardDuty! Importing..."
        terraform import aws_guardduty_organization_admin_account.gd_admin $SECURITY_TOOLING_ID || true
        break
    else
        echo "[-] AWS backend still reports $GD_CHECK active. Attempting explicit deregistration..."
        aws guardduty disable-organization-admin-account --admin-account-id $GD_CHECK || true
        echo "    Sleeping 20s for replication..."
        sleep 20
    fi
done

echo "Deregistering Security Hub Admins and waiting for propagation..."
while true; do
    SH_CHECK=$(aws securityhub list-organization-admin-accounts --query "AdminAccounts[0].AccountId" --output text || echo "None")
    
    if [ "$SH_CHECK" == "None" ] || [ -z "$SH_CHECK" ] || [ "$SH_CHECK" == "null" ]; then
        echo "[√] SUCCESS: Security Hub Admin cache is cleared globally."
        break
    elif [ "$SH_CHECK" == "$SECURITY_TOOLING_ID" ]; then
        echo "[√] SUCCESS: Security-Tooling is perfectly registered in Security Hub! Importing..."
        terraform import aws_securityhub_organization_admin_account.org_admin $SECURITY_TOOLING_ID || true
        break
    else
        echo "[-] AWS backend still reports $SH_CHECK active. Attempting explicit deregistration..."
        aws securityhub deregister-organization-admin-account --admin-account-id $SH_CHECK || true
        echo "    Sleeping 20s for replication..."
        sleep 20
    fi
done

# 4. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true
echo "Sleeping 20s for KMS replication..."
sleep 20
echo "=== Pre-Apply Fixes Core Loops Finished ==="
