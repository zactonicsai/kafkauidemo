#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
S=02-keycloak; load_state $S
[[ -f "$(state_file $S)" ]] || { warn "no state for $S"; exit 0; }
[[ -f "$(state_file 03-kafka)" ]] && die "Destroy 03-kafka first (it depends on Keycloak)"
for p in ${SSM_PARAMS:-}; do aws ssm delete-parameter --name "$p" 2>/dev/null || true; done
destroy_docker_host $S
rm -f "$(state_file $S)"; log "Stage $S destroyed"
