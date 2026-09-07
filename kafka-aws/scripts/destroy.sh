#!/usr/bin/env bash
# Usage: ./scripts/destroy.sh [kafka|keycloak|network|all] [--yes]
# Stages are destroyed in reverse order: kafka -> keycloak -> network.
source "$(dirname "$0")/_lib.sh"
need aws terraform
WHAT=${1:-all}

if [[ "${2:-}" != "--yes" && "${1:-}" != "--yes" ]]; then
  read -rp "Destroy '$WHAT' for project $PROJECT? Type the project name to confirm: " ans
  [[ "$ans" == "$PROJECT" ]] || { echo "Aborted."; exit 1; }
fi

case "$WHAT" in
  kafka)    tf_destroy 03-kafka ;;
  keycloak) tf_destroy 03-kafka; tf_destroy 02-keycloak ;;   # kafka depends on keycloak
  network)  tf_destroy 03-kafka; tf_destroy 02-keycloak; tf_destroy 01-network ;;
  all)      tf_destroy 03-kafka; tf_destroy 02-keycloak; tf_destroy 01-network ;;
  *) echo "unknown stage: $WHAT"; exit 1 ;;
esac

echo "=== Leftover check (tag Project=$PROJECT, region $REGION)"
chk() { if [[ -n "$2" ]]; then echo "WARNING: $1 still present: $2"; else echo "$1: gone"; fi; }
chk "EC2 instances" "$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ "$WHAT" == "all" || "$WHAT" == "network" ]]; then
  chk "NAT gateways"  "$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=tag:Project,Values=$PROJECT" "Name=state,Values=available,pending" --query 'NatGateways[].NatGatewayId' --output text)"
  chk "Elastic IPs"   "$(aws ec2 describe-addresses --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" --query 'Addresses[].PublicIp' --output text)"
  chk "Load balancers" "$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName,'$PROJECT')].LoadBalancerArn" --output text)"
  chk "VPCs"          "$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" --query 'Vpcs[].VpcId' --output text)"
fi
