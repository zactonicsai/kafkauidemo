#!/usr/bin/env bash
# Destroys EVERYTHING created by create.sh (including the hosted zone and all data).
# Usage: ./scripts/destroy.sh [--yes]
set -euo pipefail
cd "$(dirname "$0")/../terraform"

REGION=$(grep -E '^region' terraform.tfvars | cut -d'"' -f2 || true); REGION=${REGION:-us-east-1}
PROJECT=$(grep -E '^project' terraform.tfvars | cut -d'"' -f2 || true); PROJECT=${PROJECT:-kafka-stack}

if [[ "${1:-}" != "--yes" ]]; then
  echo "This deletes the VPC, NAT gateway, ALB, EC2 (all Kafka/Keycloak data) and the hosted zone."
  read -rp "Type the project name ($PROJECT) to confirm: " ans
  [[ "$ans" == "$PROJECT" ]] || { echo "Aborted."; exit 1; }
fi

echo "==> terraform destroy"
terraform destroy -input=false -auto-approve

echo "==> Verifying nothing is left behind (tag Project=$PROJECT)"
aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'Vpcs[].VpcId' --output text | grep -q . && echo "WARNING: VPC still exists" || echo "VPC: gone"
aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=tag:Project,Values=$PROJECT" "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output text | grep -q . && echo "WARNING: NAT gateway still exists" || echo "NAT gateway: gone"
aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName,'$PROJECT')].LoadBalancerArn" \
  --output text | grep -q . && echo "WARNING: ALB still exists" || echo "ALB: gone"
aws ec2 describe-addresses --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'Addresses[].PublicIp' --output text | grep -q . && echo "WARNING: Elastic IP still allocated (costs money!)" || echo "Elastic IP: gone"
echo "Done. Remember to remove the NS records at your registrar if you no longer use the zone."
