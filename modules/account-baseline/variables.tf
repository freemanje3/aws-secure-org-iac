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
  type        = string
  description = "Name of the central S3 bucket for AWS Config Delivery (located in Log Archive)"
}

variable "central_log_key_arn" {
  type        = string
  description = "ARN of the central KMS key for CloudWatch Logs"
}
