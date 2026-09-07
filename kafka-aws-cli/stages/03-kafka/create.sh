#!/usr/bin/env bash
# STAGE 3: Kafka + Kafka UI on one private EC2, published as https://kafka.<domain>.
# Reads Keycloak's issuer URL + client secret from SSM (written by stage 02).
source "$(dirname "$0")/../../lib/common.sh"
need aws envsubst
S=03-kafka
[[ -z "$(get $S INSTANCE_ID)" ]] || die "Stage $S already has state. Destroy it first."
lookup_network

KEYCLOAK_ISSUER_URL=$(aws ssm get-parameter --name "/$PROJECT/keycloak/issuer-url" --query Parameter.Value --output text 2>/dev/null || true)
[[ -n "$KEYCLOAK_ISSUER_URL" ]] || die "SSM parameter missing - run stage 02-keycloak first"
export KEYCLOAK_ISSUER_URL
export KEYCLOAK_CLIENT_SECRET=$(aws ssm get-parameter --name "/$PROJECT/keycloak/kafka-ui-client-secret" --with-decryption --query Parameter.Value --output text)

UD=$(mktemp); render_userdata "$(dirname "$0")/user_data.sh.tpl" "$UD"
create_docker_host $S kafka "${PRIVATE_SUBNETS[1]}" 8090 "$KAFKA_INSTANCE_TYPE" "$KAFKA_ROOT_VOLUME_GB" "$UD"; rm -f "$UD"
publish_service $S kafka-ui 8090 /actuator/health "$KAFKA_UI_HOST" 20

echo -n "Waiting for Kafka UI to be healthy behind the ALB (3-6 min)"; wait_healthy "$TG_ARN"
log "Kafka UI: https://$KAFKA_UI_HOST   (alice / ALICE_PASSWORD, bob / BOB_PASSWORD)"
log "Shell:    aws ssm start-session --target $INSTANCE_ID"
