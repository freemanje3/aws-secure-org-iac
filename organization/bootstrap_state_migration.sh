#!/bin/bash
set -e

# Pull the remote states to a temporary local workspace
cd ../bootstrap
terraform init
terraform state pull > bootstrap.tfstate
cd ../organization
terraform state pull > org.tfstate

# Perform cross-state migration of Management resources
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_s3_account_public_access_block.management 'module.management_baseline.aws_s3_account_public_access_block.baseline' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_ebs_encryption_by_default.management 'module.management_baseline.aws_ebs_encryption_by_default.baseline' || true

terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_kms_key.management_storage_key 'module.management_baseline.aws_kms_key.storage_key' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_kms_alias.management_storage_key_alias 'module.management_baseline.aws_kms_alias.storage_key_alias' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_ebs_default_kms_key.management_default 'module.management_baseline.aws_ebs_default_kms_key.default' || true

terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_vpc.management_vpc 'module.management_baseline.aws_vpc.vpc' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_subnet.management_isolated_subnet 'module.management_baseline.aws_subnet.isolated_subnet' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_route_table.management_isolated_rt 'module.management_baseline.aws_route_table.isolated_rt' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_route_table_association.management_isolated_rta 'module.management_baseline.aws_route_table_association.isolated_rta' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_vpc_endpoint.management_s3_gateway 'module.management_baseline.aws_vpc_endpoint.s3_gateway' || true
terraform state mv -state=../bootstrap/bootstrap.tfstate -state-out=org.tfstate aws_vpc_endpoint.management_dynamodb_gateway 'module.management_baseline.aws_vpc_endpoint.dynamodb_gateway' || true

# Push modified states back
terraform state push org.tfstate
cd ../bootstrap
terraform init
terraform state push bootstrap.tfstate
