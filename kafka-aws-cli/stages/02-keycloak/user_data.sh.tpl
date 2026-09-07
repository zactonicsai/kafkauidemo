# ---- Keycloak stack (appended after Docker install) ----
mkdir -p /opt/keycloak-stack/import
cd /opt/keycloak-stack

cat > docker-compose.yml <<'YML'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:26.7
    container_name: keycloak
    restart: unless-stopped
    command: ["start-dev", "--import-realm"]
    ports:
      - "8080:8080"                       # only the ALB security group can reach this
    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: "${KEYCLOAK_ADMIN_PASSWORD}"
      KC_HOSTNAME: https://${KEYCLOAK_HOST}
      KC_PROXY_HEADERS: xforwarded        # ALB terminates TLS
      KC_HTTP_ENABLED: "true"
      KC_HEALTH_ENABLED: "true"
    volumes:
      - ./import:/opt/keycloak/data/import:ro
      - keycloak-data:/opt/keycloak/data/h2
volumes:
  keycloak-data:
YML

cat > import/realm-kafka.json <<'JSON'
{
  "realm": "kafka",
  "displayName": "Kafka",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "accessTokenLifespan": 300,
  "roles": {
    "realm": [
      { "name": "kafka-admin",  "description": "Full access in Kafka UI" },
      { "name": "kafka-viewer", "description": "Read-only access in Kafka UI" }
    ]
  },
  "clients": [
    {
      "clientId": "kafka-ui",
      "name": "Kafka UI",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "clientAuthenticatorType": "client-secret",
      "secret": "${KEYCLOAK_CLIENT_SECRET}",
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "rootUrl": "https://${KAFKA_UI_HOST}",
      "baseUrl": "https://${KAFKA_UI_HOST}",
      "redirectUris": ["https://${KAFKA_UI_HOST}/login/oauth2/code/keycloak"],
      "webOrigins": ["https://${KAFKA_UI_HOST}"],
      "attributes": {
        "post.logout.redirect.uris": "https://${KAFKA_UI_HOST}/*",
        "pkce.code.challenge.method": ""
      },
      "defaultClientScopes": ["openid", "profile", "email", "roles"],
      "protocolMappers": [
        {
          "name": "realm-roles-flat",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "multivalued": "true",
            "claim.name": "roles",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        }
      ]
    }
  ],
  "users": [
    {
      "username": "alice", "email": "alice@${KEYCLOAK_HOST}", "firstName": "Alice", "lastName": "Admin",
      "enabled": true, "emailVerified": true,
      "credentials": [ { "type": "password", "value": "${ALICE_PASSWORD}", "temporary": false } ],
      "realmRoles": ["kafka-admin"]
    },
    {
      "username": "bob", "email": "bob@${KEYCLOAK_HOST}", "firstName": "Bob", "lastName": "Viewer",
      "enabled": true, "emailVerified": true,
      "credentials": [ { "type": "password", "value": "${BOB_PASSWORD}", "temporary": false } ],
      "realmRoles": ["kafka-viewer"]
    }
  ]
}
JSON
chmod 600 import/realm-kafka.json

cat > /etc/systemd/system/keycloak-stack.service <<'UNIT'
[Unit]
Description=Keycloak (docker compose)
Requires=docker.service
After=docker.service network-online.target
[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/keycloak-stack
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now keycloak-stack.service
