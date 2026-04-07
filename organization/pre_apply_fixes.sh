#!/bin/bash
echo "=== Pre-Apply Fixes Pipeline ==="

echo "--- CRITICAL DEBUG START ---"
GD_ADMIN=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[0].AdminAccountId" --output text || echo "FAILED_GD")
SH_ADMIN=$(aws securityhub list-organization-admin-accounts --query "AdminAccounts[0].AccountId" --output text || echo "FAILED_SH")

echo "=========================================================="
echo "FATAL DIAGNOSTIC: GUARDDUTY ACTIVE ADMIN: $GD_ADMIN"
echo "FATAL DIAGNOSTIC: SECURITYHUB ACTIVE ADMIN: $SH_ADMIN"
echo "=========================================================="

echo "Intentionally exiting pipeline with Code 1 to expose these logs to you. Please copy the logs and paste them in Chat!"
exit 1
