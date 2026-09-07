#!/usr/bin/env bash
# Destroys stage 01 in reverse order. Stages 02/03 must be destroyed first.
source "$(dirname "$0")/../../lib/common.sh"
need aws jq
S=01-network; load_state $S
[[ -n "${VPC_ID:-}" ]] || { warn "no state for $S"; exit 0; }

if [[ -n "${ALB_ARN:-}" ]]; then
  log "ALB listeners + load balancer"
  for l in $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'Listeners[].ListenerArn' --output text 2>/dev/null); do
    aws elbv2 delete-listener --listener-arn "$l" || true
  done
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" || true
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" || true
  sleep 20   # ENIs take a moment to release
fi
[[ -n "${CERT_ARN:-}" ]] && { log "ACM certificate"; aws acm delete-certificate --certificate-arn "$CERT_ARN" || true; }

if [[ -n "${ZONE_ID:-}" ]]; then
  log "Hosted zone (deleting non-NS/SOA records first)"
  aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
    --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`]' --output json | jq -c '.[]' | while read -r rr; do
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
      --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":$rr}]}" >/dev/null || true
  done
  aws route53 delete-hosted-zone --id "$ZONE_ID" >/dev/null || true
fi

if [[ -n "${NAT_ID:-}" ]]; then
  log "NAT gateway (takes ~1-2 min)"
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null || true
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID" || true
fi
[[ -n "${EIP_ID:-}" ]] && { log "Elastic IP"; aws ec2 release-address --allocation-id "$EIP_ID" || true; }

log "Route tables"
for rt in ${RT_PUB:-} ${RT_PRIV:-}; do
  for a in $(aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text 2>/dev/null); do
    aws ec2 disassociate-route-table --association-id "$a" || true
  done
  aws ec2 delete-route-table --route-table-id "$rt" || true
done

log "Subnets"
for s in ${PUBLIC_SUBNETS:-} ${PRIVATE_SUBNETS:-}; do aws ec2 delete-subnet --subnet-id "$s" || true; done

[[ -n "${ALB_SG:-}" ]] && { log "ALB security group"; aws ec2 delete-security-group --group-id "$ALB_SG" || true; }

if [[ -n "${IGW_ID:-}" ]]; then
  log "Internet gateway"
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" || true
fi

log "VPC"
aws ec2 delete-vpc --vpc-id "$VPC_ID" && rm -f "$(state_file $S)" && log "Stage $S destroyed" \
  || warn "VPC delete failed - something still references it; fix and re-run"
