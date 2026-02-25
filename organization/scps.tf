# organization/scps.tf

################################################################################
# 7. Organizational Guardrails (SCPs)
################################################################################

resource "aws_organizations_policy" "protect_central_logging" {
  name        = "ProtectCentralLoggingArchitecture"
  description = "Prevents tampering with centralized logs and encryption keys"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.scp_protect_logging.json
}

resource "aws_organizations_policy_attachment" "secure_root_attachment" {
  policy_id = aws_organizations_policy.protect_central_logging.id
  target_id = aws_organizations_organization.org.roots[0].id
}

data "aws_iam_policy_document" "scp_protect_logging" {
  statement {
    sid       = "PreventLogDeletion"
    effect    = "Deny"
    actions   = ["logs:DeleteLogGroup"]
    resources = ["*"]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }

  statement {
    sid    = "PreventCentralKeyTampering"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:PutKeyPolicy"
    ]
    resources = [aws_kms_key.central_log_key.arn]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }

  statement {
    sid       = "EnforceSecureTransportS3"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}