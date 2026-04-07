#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

# 1. Manually resolve S3 BPA deletion loops
echo "Cleaning up S3 BPA loops..."
SECURITY_TOOLING_ID=$(aws organizations list-accounts --query "Accounts[?Name=='Security-Tooling'].Id" --output text)
if [ -n "$SECURITY_TOOLING_ID" ]; then
    aws s3control delete-public-access-block --account-id $SECURITY_TOOLING_ID || true
# 2. KMS Policy Pipeline Race Condition Fix
echo "Targeting KMS Policy explicitly before main execution..."
terraform apply -target=aws_kms_key.central_log_key -auto-approve || true
echo "Sleeping 20s for KMS replication..."
sleep 20
echo "=== Pre-Apply Fixes Core Loops Finished ==="
