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

  # Enable point in time recovery
  point_in_time_recovery {
    enabled = true
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

# ==========================================
# 5. Account Baselines (Management Account)
# ==========================================
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

resource "aws_s3_account_public_access_block" "management" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "management" {
  enabled = true
}


# ==========================================
# 6. General Storage CMK (Management Account)
# ==========================================

resource "aws_kms_key" "management_storage_key" {
  description             = "CMK for general storage (EBS, S3, RDS) in Management Account"
  deletion_window_in_days = 30
  enable_key_rotation     = true # Required by NIST 800-53
  policy                  = data.aws_iam_policy_document.management_storage_key_policy.json
}

resource "aws_kms_alias" "management_storage_key_alias" {
  name          = "alias/management-storage-key"
  target_key_id = aws_kms_key.management_storage_key.key_id
}

data "aws_iam_policy_document" "management_storage_key_policy" {
  # Standard decentralized policy: Trust the local account IAM to delegate access
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

# Force all new EBS volumes in the Management account to use this specific CMK
resource "aws_ebs_default_kms_key" "management_default" {
  key_arn    = aws_kms_key.management_storage_key.arn
  depends_on = [aws_ebs_encryption_by_default.management] # Ensures the baseline from the last step exists
}

# ==========================================
# 7. Secure Networking & Gateway Endpoints (Management Account)
# ==========================================

resource "aws_vpc" "management_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# The Isolated Subnet (/24 as requested)
resource "aws_subnet" "management_isolated_subnet" {
  vpc_id     = aws_vpc.management_vpc.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_route_table" "management_isolated_rt" {
  vpc_id = aws_vpc.management_vpc.id
}

resource "aws_route_table_association" "management_isolated_rta" {
  subnet_id      = aws_subnet.management_isolated_subnet.id
  route_table_id = aws_route_table.management_isolated_rt.id
}

# 1. S3 Gateway Endpoint
resource "aws_vpc_endpoint" "management_s3_gateway" {
  vpc_id            = aws_vpc.management_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.management_isolated_rt.id]
}

# 2. DynamoDB Gateway Endpoint
resource "aws_vpc_endpoint" "management_dynamodb_gateway" {
  vpc_id            = aws_vpc.management_vpc.id
  service_name      = "com.amazonaws.us-east-1.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.management_isolated_rt.id]
}