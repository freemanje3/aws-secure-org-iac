# -------------------------------------------------------------
# 1. AWS Account Security Baseline
# -------------------------------------------------------------

resource "aws_s3_account_public_access_block" "baseline" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "baseline" {
  enabled = true
}

# General Storage CMK
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "storage_key" {
  description             = "CMK for general storage (EBS, S3, RDS) in ${var.account_name_prefix} Account"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.storage_key_policy.json
}

resource "aws_kms_alias" "storage_key_alias" {
  name          = "alias/${var.account_name_prefix}-storage-key"
  target_key_id = aws_kms_key.storage_key.key_id
}

data "aws_iam_policy_document" "storage_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_ebs_default_kms_key" "default" {
  key_arn    = aws_kms_key.storage_key.arn
  depends_on = [aws_ebs_encryption_by_default.baseline]
}

# -------------------------------------------------------------
# 2. Secure Networking
# -------------------------------------------------------------

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "isolated_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.isolated_subnet_cidr
}

resource "aws_route_table" "isolated_rt" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "isolated_rta" {
  subnet_id      = aws_subnet.isolated_subnet.id
  route_table_id = aws_route_table.isolated_rt.id
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.isolated_rt.id]
}

resource "aws_vpc_endpoint" "dynamodb_gateway" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.us-east-1.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.isolated_rt.id]
}

# -------------------------------------------------------------
# 3. AWS Config Recorder
# -------------------------------------------------------------

resource "aws_iam_role" "config_role" {
  name = "AWSConfigRole-${var.account_name_prefix}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "config.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "config_policy_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "recorder" {
  name     = "${var.account_name_prefix}-config-recorder"
  role_arn = aws_iam_role.config_role.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "delivery" {
  name           = "${var.account_name_prefix}-config-delivery"
  s3_bucket_name = var.central_config_bucket_name

  depends_on = [
    aws_config_configuration_recorder.recorder
  ]
}

resource "aws_config_configuration_recorder_status" "status" {
  name       = aws_config_configuration_recorder.recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.delivery]
}

# -------------------------------------------------------------
# 4. VPC Flow Logs
# -------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/${var.account_name_prefix}"
  retention_in_days = 90
  kms_key_id        = var.central_log_key_arn
}

resource "aws_iam_role" "flow_logs_role" {
  name = "${var.account_name_prefix}VPCFlowLogsRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs_policy" {
  name = "${var.account_name_prefix}VPCFlowLogsPolicy"
  role = aws_iam_role.flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc.id
}

# -------------------------------------------------------------
# 5. GuardDuty Detector
# -------------------------------------------------------------

resource "aws_guardduty_detector" "detector" {
  enable = true
}

resource "aws_cloudwatch_log_group" "guardduty_logs" {
  name              = "/aws/events/guardduty/${var.account_name_prefix}"
  retention_in_days = 90
  kms_key_id        = var.central_log_key_arn
}

resource "aws_cloudwatch_log_resource_policy" "events_to_cwl" {
  policy_name = "${var.account_name_prefix}EventBridgeToCWL"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.guardduty_logs.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "guardduty_rule" {
  name        = "${var.account_name_prefix}-guardduty-findings"
  description = "Capture GuardDuty Findings"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_target" {
  rule = aws_cloudwatch_event_rule.guardduty_rule.name
  arn  = aws_cloudwatch_log_group.guardduty_logs.arn
}

# -------------------------------------------------------------
# 6. Security Hub & Compliance Standards
# -------------------------------------------------------------

resource "aws_securityhub_account" "securityhub" {
  lifecycle {
    ignore_changes = [
      enable_default_standards,
      control_finding_generator,
      auto_enable_controls,
    ]
  }
}

resource "aws_securityhub_standards_subscription" "nist_800_53_r5" {
  depends_on    = [aws_securityhub_account.securityhub]
  standards_arn = "arn:aws:securityhub:us-east-1::standards/nist-800-53/v/5.0.0"
}
