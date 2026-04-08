# organization/scp.tf

resource "aws_organizations_policy" "require_secure_s3_transport" {
  name        = "RequireSecureS3Transport"
  description = "Forces all S3 traffic across the organization to use HTTPS/TLS encrypted transit."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequireSecureTransport"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "secure_transport_root" {
  policy_id = aws_organizations_policy.require_secure_s3_transport.id
  target_id = aws_organizations_organization.org.roots[0].id
}
