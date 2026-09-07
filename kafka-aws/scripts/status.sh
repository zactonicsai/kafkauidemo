#!/usr/bin/env bash
# Shows what is running and whether the ALB targets are healthy.
set -euo pipefail
cd "$(dirname "$0")/../terraform"
REGION=$(grep -E '^region' terraform.tfvars | cut -d'"' -f2 || true); REGION=${REGION:-us-east-1}

INSTANCE_ID=$(terraform output -raw instance_id)
echo "== EC2"
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].{Id:InstanceId,Type:InstanceType,State:State.Name,PrivateIp:PrivateIpAddress}' --output table

echo "== ALB targets"
for name in keycloak kafka_ui; do
  arn=$(terraform output -json target_group_arns | jq -r ".$name")
  state=$(aws elbv2 describe-target-health --target-group-arn "$arn" --region "$REGION" \
          --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
  printf '  %-10s %s\n' "$name" "$state"
done

echo "== URLs"
echo "  $(terraform output -raw keycloak_url)"
echo "  $(terraform output -raw kafka_ui_url)"

echo "== Containers (via SSM)"
aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["docker ps --format \"table {{.Names}}\t{{.Status}}\""]' \
  --query 'Command.CommandId' --output text > /tmp/cmd_id
sleep 4
aws ssm get-command-invocation --region "$REGION" --instance-id "$INSTANCE_ID" \
  --command-id "$(cat /tmp/cmd_id)" --query 'StandardOutputContent' --output text
