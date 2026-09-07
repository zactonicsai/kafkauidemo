# ---- Kafka + Kafka UI stack (appended after Docker install) ----
mkdir -p /opt/kafka-stack/kafka-ui
cd /opt/kafka-stack

cat > docker-compose.yml <<'YML'
services:
  kafka:
    image: apache/kafka:4.3.1
    container_name: kafka
    restart: unless-stopped
    ports:
      - "9092:9092"                       # VPC-internal only (no SG rule opens it by default)
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_SHARE_COORDINATOR_STATE_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_LOG_DIRS: /var/lib/kafka/data
    volumes:
      - kafka-data:/var/lib/kafka/data
    healthcheck:
      test: ["CMD-SHELL", "/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1"]
      interval: 10s
      timeout: 10s
      retries: 12
      start_period: 20s

  kafka-ui:
    image: ghcr.io/kafbat/kafka-ui:v1.5.0
    container_name: kafka-ui
    restart: unless-stopped              # retries until Keycloak (stage 02) answers
    ports:
      - "8090:8080"
    environment:
      SPRING_CONFIG_ADDITIONAL-LOCATION: /config.yml
      SERVER_FORWARD_HEADERS_STRATEGY: framework
    volumes:
      - ./kafka-ui/config.yml:/config.yml:ro
    depends_on:
      kafka:
        condition: service_healthy
volumes:
  kafka-data:
YML

cat > kafka-ui/config.yml <<'CFG'
kafka:
  clusters:
    - name: aws
      bootstrapServers: kafka:9092

auth:
  type: OAUTH2
  oauth2:
    client:
      keycloak:
        clientId: kafka-ui
        clientSecret: "${KEYCLOAK_CLIENT_SECRET}"
        scope: openid
        client-name: Keycloak
        provider: keycloak
        authorization-grant-type: authorization_code
        issuer-uri: ${KEYCLOAK_ISSUER_URL}
        redirect-uri: https://${KAFKA_UI_HOST}/login/oauth2/code/keycloak
        user-name-attribute: preferred_username
        custom-params:
          type: oauth
          roles-field: roles

rbac:
  roles:
    - name: admins
      clusters: [ aws ]
      subjects:
        - { provider: oauth, type: role, value: kafka-admin }
      permissions:
        - { resource: applicationconfig, actions: all }
        - { resource: clusterconfig, actions: all }
        - { resource: topic, value: ".*", actions: all }
        - { resource: consumer, value: ".*", actions: all }
        - { resource: schema, value: ".*", actions: all }
        - { resource: connect, value: ".*", actions: all }
        - { resource: ksql, actions: all }
        - { resource: acl, actions: all }
        - { resource: audit, actions: all }
    - name: viewers
      clusters: [ aws ]
      subjects:
        - { provider: oauth, type: role, value: kafka-viewer }
      permissions:
        - { resource: clusterconfig, actions: [ view ] }
        - { resource: topic, value: ".*", actions: [ view, messages_read ] }
        - { resource: consumer, value: ".*", actions: [ view ] }
        - { resource: schema, value: ".*", actions: [ view ] }
        - { resource: connect, value: ".*", actions: [ view ] }
        - { resource: acl, actions: [ view ] }
CFG
chmod 600 kafka-ui/config.yml

cat > /etc/systemd/system/kafka-stack.service <<'UNIT'
[Unit]
Description=Kafka + Kafka UI (docker compose)
Requires=docker.service
After=docker.service network-online.target
[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/kafka-stack
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now kafka-stack.service
