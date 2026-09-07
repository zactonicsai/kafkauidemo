#!/usr/bin/env bash
# Shows each stage's state, instance and ALB target health.
source "$(dirname "$0")/_lib.sh"
need aws terraform jq
for s in "${STAGES[@]}"; do
  dir=$(stage_dir "$s")
  if [[ ! -f "$dir/terraform.tfstate" ]] || ! tf "$s" output >/dev/null 2>&1; then
    echo "$s: not applied"; continue
  fi
  echo "== $s"
  case "$s" in
    01-network)
      echo "  ALB: $(tf "$s" output -raw alb_dns_name)"
      echo "  NS : $(tf "$s" output -json name_servers | jq -r 'join(", ")')" ;;
    *)
      id=$(tf "$s" output -raw instance_id)
      st=$(aws ec2 describe-instances --instance-ids "$id" --region "$REGION" --query 'Reservations[0].Instances[0].State.Name' --output text)
      th=$(aws elbv2 describe-target-health --target-group-arn "$(tf "$s" output -raw target_group_arn)" --region "$REGION" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
      echo "  instance $id ($st)   target: $th"
      echo "  url: $(tf "$s" output -json | jq -r 'to_entries[] | select(.key|endswith("_url")) | .value.value')"
      echo "  shell: aws ssm start-session --target $id --region $REGION" ;;
  esac
done
