#!/usr/bin/env bash
# Fixed monthly estimate + actual month-to-date spend per stage (Cost Explorer, tag "Stage").
# Activate cost-allocation tags "Project" and "Stage" once in Billing -> Cost allocation tags.
source "$(dirname "$0")/lib/common.sh"
need aws
cat <<'TABLE'
== Estimated fixed cost (us-east-1, on-demand, 730 h/month; verify in the AWS Pricing Calculator)
  STAGE 01-network
    NAT Gateway                    $0.045/h     ~ $32.85  (+ $0.045/GB processed)
    Application Load Balancer      $0.0225/h    ~ $16.40  (+ LCUs ~$1-6)
    Public IPv4 x3 (NAT + 2 ALB)   $0.005/h ea  ~ $10.95
    Route 53 hosted zone           $0.50        ~  $0.50
    ACM certificate, IGW, VPC                      $0.00
                                             subtotal ~ $61
  STAGE 02-keycloak
    EC2 t3.small (2 GB)            $0.0208/h    ~ $15.20
    EBS gp3 20 GB                  $0.08/GB     ~  $1.60
    SSM parameters (standard)                      $0.00
                                             subtotal ~ $17
  STAGE 03-kafka
    EC2 t3.medium (4 GB)           $0.0416/h    ~ $30.40
    EBS gp3 30 GB                  $0.08/GB     ~  $2.40
                                             subtotal ~ $33
  --------------------------------------------------------------
  TOTAL                                        ~ $111-116 / month  (~$0.16 / hour)
  Idle-savings: destroy kafka+keycloak (-$50) and keep the network, or destroy all (-$111, keep $0.50 zone).
TABLE
echo
echo "== Actual month-to-date spend for Project=$PROJECT, grouped by Stage tag"
START=$(date -u +%Y-%m-01)
END=$(date -u -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -u -v+1d +%Y-%m-%d)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start="$START",End="$END" --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=TAG,Key=Stage \
  --filter "{\"Tags\":{\"Key\":\"Project\",\"Values\":[\"$PROJECT\"]}}" \
  --query 'ResultsByTime[0].Groups[].{Stage:Keys[0],USD:Metrics.UnblendedCost.Amount}' --output table
