#!/usr/bin/env bash
# Usage: ./create.sh [network|keycloak|kafka|all]   (default: all)
source "$(dirname "$0")/lib/common.sh"
need aws jq dig envsubst
aws sts get-caller-identity --query Account --output text >/dev/null || die "AWS CLI not configured"
case "${1:-all}" in
  network)  "$ROOT/stages/01-network/create.sh" ;;
  keycloak) "$ROOT/stages/02-keycloak/create.sh" ;;
  kafka)    "$ROOT/stages/03-kafka/create.sh" ;;
  all)      "$ROOT/stages/01-network/create.sh"; "$ROOT/stages/02-keycloak/create.sh"; "$ROOT/stages/03-kafka/create.sh" ;;
  *) die "unknown stage: $1" ;;
esac
