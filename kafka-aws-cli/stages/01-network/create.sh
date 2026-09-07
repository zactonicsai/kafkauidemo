#!/usr/bin/env bash
# STAGE 1: VPC, subnets, IGW, NAT, route tables, ALB security group, hosted zone,
# ACM certificate (DNS validated), public ALB with HTTP->HTTPS + HTTPS listener.
source "$(dirname "$0")/../../lib/common.sh"
need aws jq dig
S=01-network
[[ -z "$(get $S VPC_ID)" ]] || die "Stage $S already has state ($STATE_DIR/$S.env). Destroy it first."

log "VPC $VPC_CIDR"
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --tag-specifications "$(tagspec vpc $S "$PROJECT-vpc")" --query Vpc.VpcId --output text)
save $S VPC_ID "$VPC_ID"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames

log "Internet gateway"
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "$(tagspec internet-gateway $S "$PROJECT-igw")" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
save $S IGW_ID "$IGW_ID"

AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[?State==`available`].ZoneName | [0:2]' --output text))
O1=$(echo "$VPC_CIDR" | cut -d. -f1); O2=$(echo "$VPC_CIDR" | cut -d. -f2)   # 10.0.x.0/24 subnets
log "Subnets in ${AZS[*]}"
PUB=(); PRIV=()
for i in 0 1; do
  PUB[$i]=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$O1.$O2.$i.0/24" --availability-zone "${AZS[$i]}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-public-$i},{Key=Tier,Value=public},{Key=Project,Value=$PROJECT},{Key=Stage,Value=$S},{Key=ManagedBy,Value=aws-cli}]" \
    --query Subnet.SubnetId --output text)
  PRIV[$i]=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$O1.$O2.$((i+10)).0/24" --availability-zone "${AZS[$i]}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PROJECT-private-$i},{Key=Tier,Value=private},{Key=Project,Value=$PROJECT},{Key=Stage,Value=$S},{Key=ManagedBy,Value=aws-cli}]" \
    --query Subnet.SubnetId --output text)
done
save $S PUBLIC_SUBNETS "${PUB[*]}"; save $S PRIVATE_SUBNETS "${PRIV[*]}"

log "NAT gateway (takes ~2 min)"
EIP_ID=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tagspec elastic-ip $S "$PROJECT-nat-eip")" --query AllocationId --output text)
save $S EIP_ID "$EIP_ID"
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "${PUB[0]}" --allocation-id "$EIP_ID" --tag-specifications "$(tagspec natgateway $S "$PROJECT-nat")" --query NatGateway.NatGatewayId --output text)
save $S NAT_ID "$NAT_ID"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

log "Route tables"
RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(tagspec route-table $S "$PROJECT-rt-public")" --query RouteTable.RouteTableId --output text)
RT_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(tagspec route-table $S "$PROJECT-rt-private")" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 create-route --route-table-id "$RT_PRIV" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" >/dev/null
for s in "${PUB[@]}";  do aws ec2 associate-route-table --route-table-id "$RT_PUB"  --subnet-id "$s" >/dev/null; done
for s in "${PRIV[@]}"; do aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$s" >/dev/null; done
save $S RT_PUB "$RT_PUB"; save $S RT_PRIV "$RT_PRIV"

log "ALB security group (80/443 from anywhere)"
ALB_SG=$(aws ec2 create-security-group --group-name "$PROJECT-alb" --description "Public entry point" --vpc-id "$VPC_ID" \
         --tag-specifications "$(tagspec security-group $S "$PROJECT-alb")" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --ip-permissions \
  'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' \
  'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null
save $S ALB_SG "$ALB_SG"

log "Route 53 hosted zone $DOMAIN"
ZONE_ID=$(aws route53 create-hosted-zone --name "$DOMAIN" --caller-reference "$PROJECT-$(date +%s)" \
          --hosted-zone-config Comment="$PROJECT hosted zone" --query HostedZone.Id --output text | sed 's#/hostedzone/##')
save $S ZONE_ID "$ZONE_ID"
aws route53 change-tags-for-resource --resource-type hostedzone --resource-id "$ZONE_ID" --add-tags Key=Project,Value=$PROJECT Key=Stage,Value=$S
echo; echo "Set these NAME SERVERS for $DOMAIN at your registrar:"
aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output table
if [[ "${SKIP_NS:-}" != "1" ]]; then
  EXPECTED=$(aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers[0]' --output text)
  echo "Waiting for delegation (Ctrl+C to abort; the state file lets you resume with SKIP_NS=1)..."
  until dig +short NS "$DOMAIN" @8.8.8.8 | grep -qi "$EXPECTED"; do printf '.'; sleep 30; done; echo " delegated"
fi

log "ACM certificate for $KEYCLOAK_HOST + $KAFKA_UI_HOST (DNS validation)"
CERT_ARN=$(aws acm request-certificate --domain-name "$KEYCLOAK_HOST" --subject-alternative-names "$KAFKA_UI_HOST" \
           --validation-method DNS --tags Key=Project,Value=$PROJECT Key=Stage,Value=$S --query CertificateArn --output text)
save $S CERT_ARN "$CERT_ARN"
sleep 15   # validation records appear a few seconds after the request
aws acm describe-certificate --certificate-arn "$CERT_ARN" \
  --query 'Certificate.DomainValidationOptions[].ResourceRecord' --output json | jq -c '.[]' | sort -u | while read -r rr; do
  NAME=$(echo "$rr" | jq -r .Name); VALUE=$(echo "$rr" | jq -r .Value)
  aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{
    \"Name\":\"$NAME\",\"Type\":\"CNAME\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"$VALUE\"}]}}]}" >/dev/null
done
echo "Waiting for certificate validation (1-10 min)..."
aws acm wait certificate-validated --certificate-arn "$CERT_ARN"

log "Application Load Balancer"
ALB_ARN=$(aws elbv2 create-load-balancer --name "$PROJECT-alb" --type application --scheme internet-facing \
          --subnets "${PUB[@]}" --security-groups "$ALB_SG" --tags $(tags_kv $S "$PROJECT-alb") \
          --query 'LoadBalancers[0].LoadBalancerArn' --output text)
save $S ALB_ARN "$ALB_ARN"
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' >/dev/null
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTPS --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 --certificates "CertificateArn=$CERT_ARN" \
  --default-actions 'Type=fixed-response,FixedResponseConfig={StatusCode=404,ContentType=text/plain,MessageBody="Unknown host"}' >/dev/null

log "Stage $S done. ALB: $(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)"
