# shared helpers (sourced by the other scripts)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$ROOT/common.tfvars"
[[ -f "$COMMON" ]] || { echo "Missing $COMMON (copy common.tfvars.example)"; exit 1; }
PROJECT=$(grep -E '^project'     "$COMMON" | cut -d'"' -f2)
REGION=$(grep -E '^region'       "$COMMON" | cut -d'"' -f2)
DOMAIN=$(grep -E '^domain_name'  "$COMMON" | cut -d'"' -f2)
STAGES=(01-network 02-keycloak 03-kafka)

stage_dir() { echo "$ROOT/stages/$1"; }

tf() {  # tf <stage> <terraform args...>
  local dir; dir=$(stage_dir "$1"); shift
  (cd "$dir" && terraform "$@")
}

tf_apply() {  # tf_apply <stage> [extra args]
  local s=$1; shift
  local dir; dir=$(stage_dir "$s")
  local vf=(-var-file="$COMMON")
  [[ -f "$dir/terraform.tfvars" ]] && vf+=(-var-file="$dir/terraform.tfvars")
  tf "$s" init -input=false >/dev/null
  tf "$s" apply -input=false -auto-approve "${vf[@]}" "$@"
}

tf_destroy() {
  local s=$1
  local dir; dir=$(stage_dir "$s")
  [[ -f "$dir/terraform.tfstate" ]] || { echo "  (stage $s has no state, skipping)"; return; }
  local vf=(-var-file="$COMMON")
  [[ -f "$dir/terraform.tfvars" ]] && vf+=(-var-file="$dir/terraform.tfvars")
  tf "$s" destroy -input=false -auto-approve "${vf[@]}"
}

wait_healthy() {  # wait_healthy <target-group-arn>
  until [[ "$(aws elbv2 describe-target-health --target-group-arn "$1" --region "$REGION" \
              --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)" == "healthy" ]]; do
    printf '.'; sleep 20
  done; echo " healthy"
}

need() { for b in "$@"; do command -v "$b" >/dev/null || { echo "Missing: $b"; exit 1; }; done; }
