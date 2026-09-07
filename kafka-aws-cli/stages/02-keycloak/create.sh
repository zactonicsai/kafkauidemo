#!/usr/bin/env bash
# STAGE 2: Keycloak on its own private EC2, published as https://keycloak.<domain>,
# plus SSM parameters that stage 03 reads (issuer URL + client secret).
source "$(dirname "$0")/../../lib/common.sh"
need aws envsubst
S=02-keycloak
[[ -z "$(get $S INSTANCE_ID)" ]] || die "Stage $S already has state. Destroy it first."
lookup_network

UD=$(mktemp); render_userdata "$(dirname "$0")/user_data.sh.tpl" "$UD"
create_docker_host $S keycloak "${PRIVATE_SUBNETS[0]}" 8080 "$KEYCLOAK_INSTANCE_TYPE" 20 "$UD"; rm -f "$UD"
publish_service $S keycloak 8080 /realms/kafka "$KEYCLOAK_HOST" 10

log "SSM parameters for stage 03"
aws ssm put-parameter --name "/$PROJECT/keycloak/issuer-url" --type String --overwrite \
  --value "https://$KEYCLOAK_HOST/realms/kafka" >/dev/null
aws ssm put-parameter --name "/$PROJECT/keycloak/kafka-ui-client-secret" --type SecureString --overwrite \
  --value "$KEYCLOAK_CLIENT_SECRET" >/dev/null
save $S SSM_PARAMS "/$PROJECT/keycloak/issuer-url /$PROJECT/keycloak/kafka-ui-client-secret"

echo -n "Waiting for Keycloak to be healthy behind the ALB (3-6 min)"; wait_healthy "$TG_ARN"
log "Keycloak: https://$KEYCLOAK_HOST   (admin / KEYCLOAK_ADMIN_PASSWORD)"
log "Shell:    aws ssm start-session --target $INSTANCE_ID"
