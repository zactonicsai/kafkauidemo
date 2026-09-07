#!/usr/bin/env bash
# Usage: ./scripts/create.sh [network|keycloak|kafka|all]   (default: all)
#   network  -> VPC, NAT, hosted zone (waits for NS delegation), certificate, ALB
#   keycloak -> Keycloak EC2 + ALB rule + DNS record + SSM hand-off
#   kafka    -> Kafka + Kafka UI EC2 + ALB rule + DNS record
source "$(dirname "$0")/_lib.sh"
need aws terraform jq dig
WHAT=${1:-all}

aws sts get-caller-identity --query Account --output text >/dev/null || { echo "AWS CLI not configured"; exit 1; }

do_network() {
  echo "=== STAGE 01-network"
  if [[ "${SKIP_NS:-}" != "1" ]]; then
    tf_apply 01-network -target=module.dns.aws_route53_zone.this
    ZONE_ID=$(tf 01-network output -raw hosted_zone_id)
    echo; echo "Set these NAME SERVERS for $DOMAIN at your registrar:"
    aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output table
    EXPECTED=$(aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers[0]' --output text)
    echo "Waiting for delegation (Ctrl+C to abort, re-run with SKIP_NS=1 later)..."
    until dig +short NS "$DOMAIN" @8.8.8.8 | grep -qi "$EXPECTED"; do printf '.'; sleep 30; done
    echo " delegated"
  fi
  tf_apply 01-network
}

do_keycloak() {
  echo "=== STAGE 02-keycloak"
  tf_apply 02-keycloak
  echo -n "Waiting for Keycloak to be healthy behind the ALB (3-6 min)"
  wait_healthy "$(tf 02-keycloak output -raw target_group_arn)"
  echo "Keycloak: $(tf 02-keycloak output -raw keycloak_url)"
}

do_kafka() {
  echo "=== STAGE 03-kafka"
  tf_apply 03-kafka
  echo -n "Waiting for Kafka UI to be healthy behind the ALB (3-6 min)"
  wait_healthy "$(tf 03-kafka output -raw target_group_arn)"
  echo "Kafka UI: $(tf 03-kafka output -raw kafka_ui_url)"
}

case "$WHAT" in
  network)  do_network ;;
  keycloak) do_keycloak ;;
  kafka)    do_kafka ;;
  all)      do_network; do_keycloak; do_kafka ;;
  *) echo "unknown stage: $WHAT"; exit 1 ;;
esac
echo "Done."
