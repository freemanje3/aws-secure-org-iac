# organization/main.tf

################################################################################
# 1. Terraform Configuration & Backend
################################################################################

terraform {
  backend "s3" {
    bucket         = "company-tf-state-079390753901"
    key            = "organization/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
  }
}

################################################################################
# 2. Provider Definitions & Data Sources
################################################################################

# Default Provider: Management Account
provider "aws" {
  region = "us-east-1"
}

# Aliased Provider: Log Archive Account
provider "aws" {
  alias  = "log_archive"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.log_archive.id}:role/OrganizationAccountAccessRole"
  }
}

# Aliased Provider: Security Tooling Account
provider "aws" {
  alias  = "security_tooling"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.security_tooling.id}:role/OrganizationAccountAccessRole"
  }
}

# Required to dynamically fetch the Management Account ID for policies
data "aws_caller_identity" "current" {}

################################################################################
# 3. AWS Organizations & Organizational Units (OUs)
################################################################################

resource "aws_organizations_organization" "org" {
  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY"
  ]

  aws_service_access_principals = [
    "sso.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "securityhub.amazonaws.com",
    "guardduty.amazonaws.com",
    "inspector2.amazonaws.com"
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.org.roots[0].id
}
