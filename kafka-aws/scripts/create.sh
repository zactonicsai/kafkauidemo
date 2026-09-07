#!/usr/bin/env bash
# Creates the whole stack.
#   Phase 1: hosted zone only  -> you point your registrar's NS records at it
#   Phase 2: everything else   -> ACM cert validates via DNS, ALB, EC2, records
# Usage: ./scripts/create.sh            (interactive NS check)
#        ./scripts/create.sh --skip-ns  (zone already delegated, just apply)
set -euo pipefail
cd "$(dirname "$0")/../terraform"

for bin in aws terraform jq dig; do
  command -v "$bin" >/dev/null || { echo "Missing: $bin"; exit 1; }
done
[[ -f terraform.tfvars ]] || { echo "Copy terraform.tfvars.example to terraform.tfvars and edit it first."; exit 1; }

echo "==> AWS identity"
aws sts get-caller-identity --output table

DOMAIN=$(grep -E '^domain_name' terraform.tfvars | cut -d'"' -f2)
REGION=$(grep -E '^region' terraform.tfvars | cut -d'"' -f2 || true); REGION=${REGION:-us-east-1}

terraform init -input=false

# ---------------------------------------------------------------- Phase 1
if [[ "${1:-}" != "--skip-ns" ]]; then
  echo "==> Phase 1: creating Route 53 hosted zone for $DOMAIN"
  terraform apply -input=false -auto-approve -target=aws_route53_zone.main
  ZONE_ID=$(terraform output -raw hosted_zone_id)
  echo
  echo "Set these NAME SERVERS for $DOMAIN at your registrar:"
  aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output table
  echo
  echo "Waiting for delegation (checking every 30s, Ctrl+C to abort)..."
  EXPECTED=$(aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers[0]' --output text)
  until dig +short NS "$DOMAIN" @8.8.8.8 | grep -qi "$EXPECTED"; do
    printf '.'; sleep 30
  done
  echo " delegated!"
fi

# ---------------------------------------------------------------- Phase 2
echo "==> Phase 2: creating network, ALB, certificate, EC2 (5-10 min)"
terraform apply -input=false -auto-approve

INSTANCE_ID=$(terraform output -raw instance_id)
TG_KC=$(terraform output -json target_group_arns | jq -r .keycloak)
TG_UI=$(terraform output -json target_group_arns | jq -r .kafka_ui)

echo "==> Waiting for the EC2 instance to boot and the containers to become healthy (5-8 min)..."
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "$REGION"
for tg in "$TG_KC" "$TG_UI"; do
  until [[ "$(aws elbv2 describe-target-health --target-group-arn "$tg" --region "$REGION" \
              --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)" == "healthy" ]]; do
    printf '.'; sleep 20
  done
done
echo
echo "================================================================"
echo " Keycloak : $(terraform output -raw keycloak_url)   (admin / keycloak_admin_password)"
echo " Kafka UI : $(terraform output -raw kafka_ui_url)   (alice / alice_password)"
echo " Shell    : aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "================================================================"
