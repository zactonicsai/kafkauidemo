#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"
for s in 01-network 02-keycloak 03-kafka; do
  if [[ ! -f "$(state_file $s)" ]]; then echo "$s: not created"; continue; fi
  echo "== $s"; ( load_state $s
    case $s in
      01-network) echo "  VPC $VPC_ID   ALB $(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)" ;;
      *) st=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text)
         th=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
         echo "  instance $INSTANCE_ID ($st)   target: $th   https://$HOST"
         echo "  shell: aws ssm start-session --target $INSTANCE_ID" ;;
    esac )
done
