#!/usr/bin/env bash
# Usage: ./destroy.sh [kafka|keycloak|network|all] [--yes]   (reverse order, default: all)
source "$(dirname "$0")/lib/common.sh"
need aws jq
WHAT=${1:-all}
if [[ "${2:-}" != "--yes" && "${1:-}" != "--yes" ]]; then
  read -rp "Destroy '$WHAT' for project $PROJECT? Type the project name to confirm: " ans
  [[ "$ans" == "$PROJECT" ]] || die "Aborted."
fi
case "$WHAT" in
  kafka)    "$ROOT/stages/03-kafka/destroy.sh" ;;
  keycloak) "$ROOT/stages/03-kafka/destroy.sh"; "$ROOT/stages/02-keycloak/destroy.sh" ;;
  network|all) "$ROOT/stages/03-kafka/destroy.sh"; "$ROOT/stages/02-keycloak/destroy.sh"; "$ROOT/stages/01-network/destroy.sh" ;;
  *) die "unknown stage: $WHAT" ;;
esac
log "Leftover check (tag Project=$PROJECT)"
chk() { if [[ -n "$2" && "$2" != "None" ]]; then warn "$1 still present: $2"; else echo "  $1: gone"; fi; }
chk "EC2"   "$(aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)"
if [[ "$WHAT" == "all" || "$WHAT" == "network" ]]; then
  chk "NAT"   "$(aws ec2 describe-nat-gateways --filter "Name=tag:Project,Values=$PROJECT" "Name=state,Values=available,pending" --query 'NatGateways[].NatGatewayId' --output text)"
  chk "EIP"   "$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=$PROJECT" --query 'Addresses[].PublicIp' --output text)"
  chk "ALB"   "$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,'$PROJECT')].LoadBalancerArn" --output text)"
  chk "VPC"   "$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT" --query 'Vpcs[].VpcId' --output text)"
fi
