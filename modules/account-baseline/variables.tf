variable "account_name_prefix" {
  type        = string
  description = "Prefix for naming resources in this account (e.g., 'management', 'log-archive')"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC"
}

variable "isolated_subnet_cidr" {
  type        = string
  description = "The CIDR block for the isolated subnet inside the VPC"
}

variable "central_config_bucket_name" {
  description = "Name of the central S3 bucket in the Log Archive account for AWS Config delivery"
  type        = string
}

variable "manage_guardduty" {
  description = "Should Terraform explicitly manage the GuardDuty detector? (set false if Auto-Enabled by Organization)"
  type        = bool
  default     = false
}

variable "central_log_key_arn" {
  type        = string
  description = "ARN of the central KMS key for CloudWatch Logs"
}
