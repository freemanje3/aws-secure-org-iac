#!/bin/bash
echo "=== Pre-Apply Pipeline Restored ==="

# 1. Manually resolve S3 BPA deletion loops
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
fi

# 2. Obliterate Deadlocked Identity Center Ghost Permission Set
echo "Sweeping for deadlocked OrganizationAdministrator in SSO..."
INSTANCE_ARN=$(aws sso-admin list-instances --query "Instances[0].InstanceArn" --output text || echo "None")
if [ "$INSTANCE_ARN" != "None" ] && [ -n "$INSTANCE_ARN" ]; then
    PS_ARNS=$(aws sso-admin list-permission-sets --instance-arn "$INSTANCE_ARN" --query "PermissionSets" --output text || echo "")
    for arn in $PS_ARNS; do
        if [ "$arn" != "None" ] && [ -n "$arn" ]; then
            NAME=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$arn" --query "PermissionSet.Name" --output text || echo "")
            if [ "$NAME" == "OrganizationAdministrator" ]; then
                echo "Found hanging OrganizationAdministrator! Force deleting to break Terraform deadlock..."
                aws sso-admin delete-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$arn" || true
            fi
        fi
    done
fi

# 3. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true
echo "Sleeping 20s for KMS replication..."
sleep 20
echo "=== Pre-Apply Ghost Cleanser Core Loops Finished ==="
