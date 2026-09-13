#!/usr/bin/env bash
set -euo pipefail

BUCKET=poly-glot-aws-cloud-state
REGION=eu-west-2
TERRAFORM_VERSION=1.14.8
WORKDIR=$(mktemp -d)

aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null ||
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --create-bucket-configuration "LocationConstraint=$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,BlockPublicPolicy=true,IgnorePublicAcls=true,RestrictPublicBuckets=true

if ! command -v terraform >/dev/null; then
  ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
  curl -sSLo "$WORKDIR/terraform.zip" "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_$ARCH.zip"
  sudo unzip -oq "$WORKDIR/terraform.zip" terraform -d /usr/local/bin
fi

git clone --depth 1 --quiet https://github.com/poly-glot/aws-cloud "$WORKDIR/aws-cloud"
cd "$WORKDIR/aws-cloud/terraform"
terraform init -input=false
terraform apply -input=false -auto-approve -target=module.github_oidc

echo
echo "INFRA_ROLE_ARN=$(terraform output -raw infra_role_arn)"
echo "ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)"
echo "LAMBDA_CONCURRENCY=$(aws lambda get-account-settings --region "$REGION" --query AccountLimit.ConcurrentExecutions --output text)"
