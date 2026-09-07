#!/usr/bin/env bash
# Prints (1) the fixed monthly estimate and (2) actual month-to-date spend from Cost Explorer.
# Cost Explorer needs the "Project" cost-allocation tag activated once in
# Billing -> Cost allocation tags (takes up to 24h to start showing data).
set -euo pipefail
cd "$(dirname "$0")/../terraform"
PROJECT=$(grep -E '^project' terraform.tfvars | cut -d'"' -f2 || true); PROJECT=${PROJECT:-kafka-stack}

cat <<TABLE
== Estimated fixed cost (us-east-1, on-demand, 730 h/month; verify with the AWS Pricing Calculator)
  EC2 t3.medium (4 GB)            \$0.0416/h   ~ \$30.40
  EBS gp3 30 GB                   \$0.08/GB    ~  \$2.40
  NAT Gateway                     \$0.045/h    ~ \$32.85  (+ \$0.045/GB processed)
  Application Load Balancer       \$0.0225/h   ~ \$16.40  (+ LCUs, ~\$1-6 at low traffic)
  Public IPv4 addresses (3)       \$0.005/h ea ~ \$10.95  (1 NAT EIP + 2 ALB)
  Route 53 hosted zone            \$0.50/zone  ~  \$0.50  (+ \$0.40 / million queries)
  ACM certificate                                \$0.00
  SSM Session Manager                            \$0.00
  Data transfer out (first 100 GB free)          ~\$0.09/GB after that
  --------------------------------------------------------
  TOTAL                                        ~ \$95-100 / month  (~\$0.13 / hour)
TABLE

echo
echo "== Actual month-to-date spend for tag Project=$PROJECT"
START=$(date -u +%Y-%m-01)
END=$(date -u -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -u -v+1d +%Y-%m-%d)
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start="$START",End="$END" --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
  --filter "{\"Tags\":{\"Key\":\"Project\",\"Values\":[\"$PROJECT\"]}}" \
  --query 'ResultsByTime[0].Groups[].{Service:Keys[0],USD:Metrics.UnblendedCost.Amount}' --output table
