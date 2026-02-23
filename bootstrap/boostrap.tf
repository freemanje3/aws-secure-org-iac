terraform {
  backend "s3" {
    bucket         = "company-tf-state-079390753901"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1" # Update to your preferred management region
}

# Dynamically fetches your current Account ID
data "aws_caller_identity" "current" {}

# ==========================================
# 1. Customer Managed Key (CMK)
# ==========================================
resource "aws_kms_key" "terraform_state" {
  description             = "CMK for Terraform State S3 and DynamoDB"
  deletion_window_in_days = 30
  enable_key_rotation     = true # Enterprise best practice

  # This policy delegates access management to IAM, 
  # allowing your admin users and GitHub Actions to use the key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state-key"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ==========================================
# 2. S3 State Bucket
# ==========================================
resource "aws_s3_bucket" "terraform_state" {
  # Bucket names must be globally unique
  bucket = "company-tf-state-${data.aws_caller_identity.current.account_id}" 
}

# Keep a history of your state files for disaster recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Force encryption using your new CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Lock down the bucket from the public internet
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# 3. DynamoDB State Lock Table
# ==========================================
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST" # Cheapest option for this use case
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Encrypt the lock table with your CMK
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }
}

# ==========================================
# 4. GitHub Actions OIDC Integration
# ==========================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # AWS natively trusts GitHub now, but Terraform requires a thumbprint. 
  # This is a standard GitHub thumbprint.
  thumbprint_list = ["1b511abead59c6ce207077c0bf0e0043b1382612"] 
}

resource "aws_iam_role" "github_actions" {
  name = "GitHubActionsTerraformRole"

  # The Trust Policy: Only allow YOUR specific repo to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          # CHANGE THIS LINE TO YOUR ORG AND REPO
          "token.actions.githubusercontent.com:sub": "repo:freemanje3/aws-secure-org-iac:*" 
        },
        StringEquals = {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Grant the GitHub role Administrator access so it can build your AWS Org
resource "aws_iam_role_policy_attachment" "github_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
