# Shared helpers. Source this at the top of every script.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/config.env" ]] || { echo "Missing $ROOT/config.env (copy config.env.example)"; exit 1; }
# shellcheck source=/dev/null
source "$ROOT/config.env"
export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
export KEYCLOAK_HOST="keycloak.$DOMAIN" KAFKA_UI_HOST="kafka.$DOMAIN"
export KEYCLOAK_ADMIN_PASSWORD KEYCLOAK_CLIENT_SECRET ALICE_PASSWORD BOB_PASSWORD   # for envsubst
STATE_DIR="$ROOT/state"; mkdir -p "$STATE_DIR"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need() { for b in "$@"; do command -v "$b" >/dev/null || die "Missing tool: $b"; done; }

# ---- tiny state store: state/<stage>.env with KEY=value lines --------------
state_file() { echo "$STATE_DIR/$1.env"; }
save() {  # save <stage> <KEY> <value>
  local f; f=$(state_file "$1"); touch "$f"
  grep -v "^$2=" "$f" > "$f.tmp" || true; echo "$2=$3" >> "$f.tmp"; mv "$f.tmp" "$f"
}
get() {  # get <stage> <KEY>   (empty if absent)
  local f; f=$(state_file "$1"); [[ -f "$f" ]] && grep "^$2=" "$f" | cut -d= -f2- || true
}
load_state() { local f; f=$(state_file "$1"); [[ -f "$f" ]] && source "$f" || true; }

# ---- tag helpers --------------------------------------------------------------
# tags <stage> <Name> -> ec2 --tag-specifications value for a resource type
tagspec() {  # tagspec <resource-type> <stage> <name>
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$3},{Key=Project,Value=$PROJECT},{Key=ManagedBy,Value=aws-cli},{Key=Stage,Value=$2}]"
}
tags_kv() {  # for resources using --tags Key=..,Value=..
  echo "Key=Project,Value=$PROJECT Key=ManagedBy,Value=aws-cli Key=Stage,Value=$1 Key=Name,Value=$2"
}

# ---- lookups of stage-01 resources by tag/name (no state needed) ---------------
lookup_network() {
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$PROJECT-vpc" --query 'Vpcs[0].VpcId' --output text)
  [[ "$VPC_ID" != "None" && -n "$VPC_ID" ]] || die "VPC $PROJECT-vpc not found - run stage 01-network first"
  PRIVATE_SUBNETS=($(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private" \
                     --query 'sort_by(Subnets,&Tags[?Key==`Name`]|[0].Value)[].SubnetId' --output text))
  ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$PROJECT-alb" \
              --query 'SecurityGroups[0].GroupId' --output text)
  ALB_ARN=$(aws elbv2 describe-load-balancers --names "$PROJECT-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
  ALB_DNS=$(aws elbv2 describe-load-balancers --names "$PROJECT-alb" --query 'LoadBalancers[0].DNSName' --output text)
  ALB_ZONE=$(aws elbv2 describe-load-balancers --names "$PROJECT-alb" --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)
  HTTPS_LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'Listeners[?Port==`443`].ListenerArn|[0]' --output text)
  ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN." --query 'HostedZones[0].Id' --output text | sed 's#/hostedzone/##')
}

# ---- Route 53 alias record UPSERT / DELETE ------------------------------------
alias_record() {  # alias_record UPSERT|DELETE <host> <alb_dns> <alb_zone> <zone_id>
  aws route53 change-resource-record-sets --hosted-zone-id "$5" --change-batch "{
    \"Changes\":[{\"Action\":\"$1\",\"ResourceRecordSet\":{\"Name\":\"$2\",\"Type\":\"A\",
      \"AliasTarget\":{\"HostedZoneId\":\"$4\",\"DNSName\":\"$3\",\"EvaluateTargetHealth\":true}}}]}" >/dev/null
}

wait_healthy() {  # wait_healthy <target-group-arn>
  until [[ "$(aws elbv2 describe-target-health --target-group-arn "$1" \
              --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)" == "healthy" ]]; do
    printf '.'; sleep 20
  done; echo " healthy"
}

# ---- a private Docker host: IAM role + SG + EC2 (used by stages 02 and 03) ----
# create_docker_host <stage> <name> <subnet_id> <port> <instance_type> <volume_gb> <userdata_file>
create_docker_host() {
  local stage=$1 name=$2 subnet=$3 port=$4 itype=$5 vol=$6 ud=$7
  local role="$PROJECT-$name-role" profile="$PROJECT-$name-profile"

  log "IAM role $role (SSM access)"
  aws iam create-role --role-name "$role" --tags $(tags_kv "$stage" "$role") --assume-role-policy-document '{
    "Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$role" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name "$profile" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$profile" --role-name "$role"
  save "$stage" ROLE_NAME "$role"; save "$stage" PROFILE_NAME "$profile"
  sleep 10   # IAM propagation

  log "Security group $PROJECT-$name (port $port from ALB only)"
  local sg
  sg=$(aws ec2 create-security-group --group-name "$PROJECT-$name" --description "$name: only ALB" --vpc-id "$VPC_ID" \
       --tag-specifications "$(tagspec security-group "$stage" "$PROJECT-$name")" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port "$port" --source-group "$ALB_SG_ID" >/dev/null
  save "$stage" SG_ID "$sg"

  log "EC2 $itype in private subnet $subnet"
  local ami id
  ami=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
  id=$(aws ec2 run-instances --image-id "$ami" --instance-type "$itype" --subnet-id "$subnet" --no-associate-public-ip-address \
       --security-group-ids "$sg" --iam-instance-profile "Name=$profile" --user-data "file://$ud" \
       --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$vol,\"VolumeType\":\"gp3\",\"Encrypted\":true}}]" \
       --metadata-options HttpTokens=required \
       --tag-specifications "$(tagspec instance "$stage" "$PROJECT-$name")" "$(tagspec volume "$stage" "$PROJECT-$name")" \
       --query 'Instances[0].InstanceId' --output text)
  save "$stage" INSTANCE_ID "$id"
  aws ec2 wait instance-running --instance-ids "$id"
  INSTANCE_ID=$id
}

# publish_service <stage> <name> <port> <health_path> <host> <priority>
publish_service() {
  local stage=$1 name=$2 port=$3 hc=$4 host=$5 prio=$6 tg
  log "Target group + ALB host rule for https://$host"
  tg=$(aws elbv2 create-target-group --name "$PROJECT-$name" --protocol HTTP --port "$port" --vpc-id "$VPC_ID" --target-type instance \
       --health-check-path "$hc" --matcher HttpCode=200 --health-check-interval-seconds 30 --healthy-threshold-count 2 --unhealthy-threshold-count 5 \
       --tags $(tags_kv "$stage" "$PROJECT-$name") --query 'TargetGroups[0].TargetGroupArn' --output text)
  aws elbv2 register-targets --target-group-arn "$tg" --targets "Id=$INSTANCE_ID,Port=$port"
  local rule
  rule=$(aws elbv2 create-rule --listener-arn "$HTTPS_LISTENER_ARN" --priority "$prio" \
         --conditions "Field=host-header,Values=$host" --actions "Type=forward,TargetGroupArn=$tg" \
         --tags $(tags_kv "$stage" "$PROJECT-$name") --query 'Rules[0].RuleArn' --output text)
  alias_record UPSERT "$host" "$ALB_DNS" "$ALB_ZONE" "$ZONE_ID"
  save "$stage" TG_ARN "$tg"; save "$stage" RULE_ARN "$rule"; save "$stage" HOST "$host"
  TG_ARN=$tg
}

# destroy_docker_host <stage>  (reverse of publish_service + create_docker_host)
destroy_docker_host() {
  local stage=$1; load_state "$stage"
  [[ -n "${RULE_ARN:-}" ]]    && { log "ALB rule";      aws elbv2 delete-rule --rule-arn "$RULE_ARN" || true; }
  if [[ -n "${HOST:-}" ]]; then
    lookup_network 2>/dev/null || true
    [[ -n "${ZONE_ID:-}" ]] && { log "DNS record $HOST"; alias_record DELETE "$HOST" "$ALB_DNS" "$ALB_ZONE" "$ZONE_ID" 2>/dev/null || true; }
  fi
  [[ -n "${TG_ARN:-}" ]]      && { log "Target group";  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" || true; }
  if [[ -n "${INSTANCE_ID:-}" ]]; then
    log "Terminating $INSTANCE_ID"; aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null || true
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" || true
  fi
  [[ -n "${SG_ID:-}" ]]       && { log "Security group"; aws ec2 delete-security-group --group-id "$SG_ID" || true; }
  if [[ -n "${PROFILE_NAME:-}" ]]; then
    log "IAM role/profile"
    aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" 2>/dev/null || true
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
  fi
}

render_userdata() {  # render_userdata <template> <out>  - Docker install + envsubst'd template
  local vars='${KEYCLOAK_HOST} ${KAFKA_UI_HOST} ${KEYCLOAK_ADMIN_PASSWORD} ${KEYCLOAK_CLIENT_SECRET} ${ALICE_PASSWORD} ${BOB_PASSWORD} ${KEYCLOAK_ISSUER_URL}'
  { cat "$ROOT/lib/install_docker.sh"; echo; envsubst "$vars" < "$1"; } > "$2"
}
