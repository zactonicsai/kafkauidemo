#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
S=03-kafka
[[ -f "$(state_file $S)" ]] || { warn "no state for $S"; exit 0; }
destroy_docker_host $S
rm -f "$(state_file $S)"; log "Stage $S destroyed"
