#!/usr/bin/env python3
# ----------------------------------------------------------------------------
# terraform_report.py
#
# Reads the JSON that Terraform produces (from `terraform show -json` or a
# `terraform plan -out=x && terraform show -json x` file) and writes a clean
# Markdown report describing every AWS resource that was created, plus the
# AWS CLI commands needed to VIEW and DESTROY each one.
#
# Usage:
#   terraform show -json > tfstate.json
#   terraform output -json > tfoutputs.json        # optional
#   python terraform_report.py tfstate.json --outputs tfoutputs.json \
#          --region us-east-1 --out REPORT.md
#
# Requirements: Python 3.8+ and the standard library only (see requirements.txt)
# ----------------------------------------------------------------------------

import argparse            # Parses command-line flags such as --out and --region
import json                # Loads the Terraform JSON files into Python dicts
import sys                 # Used to exit with an error code and print to stderr
from datetime import datetime, timezone   # Timestamps the report header
from pathlib import Path   # Cross-platform file path handling for read/write
from typing import Any, Dict, List, Optional   # Type hints for readability


# ----------------------------------------------------------------------------
# 1. Resource "recipes"
#
# Each key is a Terraform resource type. Each value is a dict with:
#   label   - human-friendly name printed in the report
#   id_attr - which attribute in the Terraform state holds the AWS identifier
#   view    - a template of AWS CLI commands to inspect the resource
#   destroy - a template of AWS CLI commands to delete the resource
#
# Templates use {id}, {name}, {region} and any state attribute wrapped in
# braces, e.g. {bucket}. Unknown placeholders are left untouched so the
# report is still readable even when an attribute is missing.
# ----------------------------------------------------------------------------
RECIPES: Dict[str, Dict[str, Any]] = {
    "aws_instance": {                                             # EC2 virtual machine
        "label": "EC2 Instance",
        "id_attr": "id",
        "view": ["aws ec2 describe-instances --instance-ids {id} --region {region}"],
        "destroy": ["aws ec2 terminate-instances --instance-ids {id} --region {region}"],
    },
    "aws_ebs_volume": {                                           # Block storage disk
        "label": "EBS Volume",
        "id_attr": "id",
        "view": ["aws ec2 describe-volumes --volume-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-volume --volume-id {id} --region {region}"],
    },
    "aws_key_pair": {                                             # SSH key pair
        "label": "EC2 Key Pair",
        "id_attr": "key_name",
        "view": ["aws ec2 describe-key-pairs --key-names {id} --region {region}"],
        "destroy": ["aws ec2 delete-key-pair --key-name {id} --region {region}"],
    },
    "aws_vpc": {                                                  # Virtual network
        "label": "VPC",
        "id_attr": "id",
        "view": ["aws ec2 describe-vpcs --vpc-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-vpc --vpc-id {id} --region {region}"],
    },
    "aws_subnet": {                                               # Sub-range of a VPC
        "label": "Subnet",
        "id_attr": "id",
        "view": ["aws ec2 describe-subnets --subnet-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-subnet --subnet-id {id} --region {region}"],
    },
    "aws_internet_gateway": {                                     # Public internet door
        "label": "Internet Gateway",
        "id_attr": "id",
        "view": ["aws ec2 describe-internet-gateways --internet-gateway-ids {id} --region {region}"],
        "destroy": [
            "aws ec2 detach-internet-gateway --internet-gateway-id {id} --vpc-id {vpc_id} --region {region}",
            "aws ec2 delete-internet-gateway --internet-gateway-id {id} --region {region}",
        ],
    },
    "aws_nat_gateway": {                                          # Outbound-only gateway
        "label": "NAT Gateway",
        "id_attr": "id",
        "view": ["aws ec2 describe-nat-gateways --nat-gateway-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-nat-gateway --nat-gateway-id {id} --region {region}"],
    },
    "aws_eip": {                                                  # Elastic (static) IP
        "label": "Elastic IP",
        "id_attr": "id",
        "view": ["aws ec2 describe-addresses --allocation-ids {id} --region {region}"],
        "destroy": ["aws ec2 release-address --allocation-id {id} --region {region}"],
    },
    "aws_route_table": {                                          # Routing rules
        "label": "Route Table",
        "id_attr": "id",
        "view": ["aws ec2 describe-route-tables --route-table-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-route-table --route-table-id {id} --region {region}"],
    },
    "aws_security_group": {                                       # Firewall rules
        "label": "Security Group",
        "id_attr": "id",
        "view": ["aws ec2 describe-security-groups --group-ids {id} --region {region}"],
        "destroy": ["aws ec2 delete-security-group --group-id {id} --region {region}"],
    },
    "aws_lb": {                                                   # Application/Network LB
        "label": "Load Balancer",
        "id_attr": "arn",
        "view": ["aws elbv2 describe-load-balancers --load-balancer-arns {id} --region {region}"],
        "destroy": ["aws elbv2 delete-load-balancer --load-balancer-arn {id} --region {region}"],
    },
    "aws_s3_bucket": {                                            # Object storage bucket
        "label": "S3 Bucket",
        "id_attr": "bucket",
        "view": ["aws s3api get-bucket-location --bucket {id}", "aws s3 ls s3://{id}"],
        "destroy": ["aws s3 rb s3://{id} --force"],               # --force empties the bucket first
    },
    "aws_iam_role": {                                             # IAM role
        "label": "IAM Role",
        "id_attr": "name",
        "view": ["aws iam get-role --role-name {id}"],
        "destroy": ["aws iam delete-role --role-name {id}"],
    },
    "aws_iam_policy": {                                           # Customer-managed policy
        "label": "IAM Policy",
        "id_attr": "arn",
        "view": ["aws iam get-policy --policy-arn {id}"],
        "destroy": ["aws iam delete-policy --policy-arn {id}"],
    },
    "aws_iam_user": {                                             # IAM user
        "label": "IAM User",
        "id_attr": "name",
        "view": ["aws iam get-user --user-name {id}"],
        "destroy": ["aws iam delete-user --user-name {id}"],
    },
    "aws_lambda_function": {                                      # Serverless function
        "label": "Lambda Function",
        "id_attr": "function_name",
        "view": ["aws lambda get-function --function-name {id} --region {region}"],
        "destroy": ["aws lambda delete-function --function-name {id} --region {region}"],
    },
    "aws_db_instance": {                                          # RDS database
        "label": "RDS Instance",
        "id_attr": "identifier",
        "view": ["aws rds describe-db-instances --db-instance-identifier {id} --region {region}"],
        "destroy": ["aws rds delete-db-instance --db-instance-identifier {id} --skip-final-snapshot --region {region}"],
    },
    "aws_dynamodb_table": {                                       # NoSQL table
        "label": "DynamoDB Table",
        "id_attr": "name",
        "view": ["aws dynamodb describe-table --table-name {id} --region {region}"],
        "destroy": ["aws dynamodb delete-table --table-name {id} --region {region}"],
    },
    "aws_sqs_queue": {                                            # Message queue
        "label": "SQS Queue",
        "id_attr": "url",
        "view": ["aws sqs get-queue-attributes --queue-url {id} --attribute-names All --region {region}"],
        "destroy": ["aws sqs delete-queue --queue-url {id} --region {region}"],
    },
    "aws_sns_topic": {                                            # Pub/sub topic
        "label": "SNS Topic",
        "id_attr": "arn",
        "view": ["aws sns get-topic-attributes --topic-arn {id} --region {region}"],
        "destroy": ["aws sns delete-topic --topic-arn {id} --region {region}"],
    },
    "aws_ecr_repository": {                                       # Container image registry
        "label": "ECR Repository",
        "id_attr": "name",
        "view": ["aws ecr describe-repositories --repository-names {id} --region {region}"],
        "destroy": ["aws ecr delete-repository --repository-name {id} --force --region {region}"],
    },
    "aws_cloudwatch_log_group": {                                 # Log storage
        "label": "CloudWatch Log Group",
        "id_attr": "name",
        "view": ["aws logs describe-log-groups --log-group-name-prefix {id} --region {region}"],
        "destroy": ["aws logs delete-log-group --log-group-name {id} --region {region}"],
    },
}

# Fallback used when a resource type is not in RECIPES above.
GENERIC_RECIPE: Dict[str, Any] = {
    "label": "AWS Resource",
    "id_attr": "id",
    "view": ["# No recipe for this type - inspect manually. ID: {id}"],
    "destroy": ["# No recipe for this type - delete manually or via `terraform destroy`. ID: {id}"],
}


# ----------------------------------------------------------------------------
# 2. Helpers for reading Terraform JSON
# ----------------------------------------------------------------------------
def load_json(path: Path) -> Any:
    """Read a file and parse it as JSON, exiting with a clear message on failure."""
    try:                                                          # Guard against missing/invalid files
        return json.loads(path.read_text(encoding="utf-8"))      # Read text and parse it
    except FileNotFoundError:                                     # File path does not exist
        sys.exit(f"ERROR: file not found: {path}")                # Print and stop with exit code 1
    except json.JSONDecodeError as exc:                           # File is not valid JSON
        sys.exit(f"ERROR: {path} is not valid JSON ({exc})")      # Print and stop


def walk_modules(module: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Recursively collect every resource from the root module and all child modules."""
    found: List[Dict[str, Any]] = []                              # Accumulator for resources
    found.extend(module.get("resources", []))                     # Add resources at this level
    for child in module.get("child_modules", []):                 # Loop over nested modules
        found.extend(walk_modules(child))                         # Recurse into each child
    return found                                                  # Return the flat list


def extract_resources(tf_json: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Pull the resource list out of either a state JSON or a plan JSON document."""
    values = tf_json.get("values")                                # `terraform show -json` on state
    if not values and "planned_values" in tf_json:                # `terraform show -json plan.out`
        values = tf_json["planned_values"]                        # Use the planned values instead
    if not values:                                                # Neither key found
        sys.exit("ERROR: no 'values' or 'planned_values' key - run `terraform show -json`.")
    root = values.get("root_module", {})                          # Top-level module block
    return walk_modules(root)                                     # Flatten all modules


def only_managed_aws(resources: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Keep only real (non-data-source) resources belonging to the AWS provider."""
    return [
        r for r in resources                                      # Iterate every resource
        if r.get("mode", "managed") == "managed"                  # Skip `data` lookups
        and r.get("type", "").startswith("aws_")                  # Only AWS provider types
    ]


def resource_id(res: Dict[str, Any], recipe: Dict[str, Any]) -> str:
    """Return the AWS identifier for a resource using the recipe's id_attr, falling back to 'id'."""
    vals = res.get("values", {}) or {}                            # Attribute map from state
    return str(vals.get(recipe["id_attr"]) or vals.get("id") or "<unknown>")   # Best available ID


def resource_name(res: Dict[str, Any]) -> str:
    """Return the Name tag if present, otherwise the Terraform resource name."""
    vals = res.get("values", {}) or {}                            # Attribute map
    tags = vals.get("tags") or vals.get("tags_all") or {}         # Tags may be under either key
    return tags.get("Name") or res.get("name", "<unnamed>")       # Prefer the Name tag


def fill(template: str, ctx: Dict[str, Any]) -> str:
    """Substitute {placeholders} in a template, leaving unknown ones intact."""
    class SafeDict(dict):                                         # dict that never raises KeyError
        def __missing__(self, key: str) -> str:                   # Called for unknown placeholders
            return "{" + key + "}"                                # Return placeholder unchanged
    return template.format_map(SafeDict(ctx))                     # Perform the safe substitution


def build_context(res: Dict[str, Any], recipe: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Create the placeholder dictionary used when filling CLI templates."""
    ctx: Dict[str, Any] = dict(res.get("values", {}) or {})       # Start with every state attribute
    ctx["id"] = resource_id(res, recipe)                          # Canonical ID for this recipe
    ctx["name"] = resource_name(res)                              # Friendly name
    ctx["region"] = ctx.get("region") or region                   # Prefer state region, else flag
    return ctx                                                    # Hand back the full context


# ----------------------------------------------------------------------------
# 3. Markdown rendering
# ----------------------------------------------------------------------------
def md_escape(text: Any) -> str:
    """Escape pipe characters so values never break Markdown tables."""
    return str(text).replace("|", "\\|")                          # Replace | with \|


def key_attributes(res: Dict[str, Any]) -> Dict[str, Any]:
    """Pick a small set of interesting attributes to show in the detail table."""
    vals = res.get("values", {}) or {}                            # Attribute map
    wanted = [                                                    # Attributes worth surfacing
        "id", "arn", "name", "bucket", "identifier", "function_name",
        "instance_type", "ami", "cidr_block", "availability_zone",
        "vpc_id", "subnet_id", "engine", "runtime", "public_ip",
        "private_ip", "dns_name", "url",
    ]
    return {k: vals[k] for k in wanted if vals.get(k) not in (None, "", [], {})}   # Only present ones


def render_report(resources: List[Dict[str, Any]], outputs: Optional[Dict[str, Any]],
                  region: str, source: str) -> str:
    """Assemble the entire Markdown document as a single string."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")   # Report timestamp
    lines: List[str] = []                                         # Collect output lines here
    add = lines.append                                            # Shorthand for appending

    # --- Header -------------------------------------------------------------
    add("# 🏗️ Terraform Deployment Report")                        # Title
    add("")
    add(f"> **Generated:** {now}  ")                               # When
    add(f"> **Source:** `{source}`  ")                              # Which file was parsed
    add(f"> **Default region:** `{region}`  ")                     # Region used for CLI commands
    add(f"> **Managed AWS resources:** **{len(resources)}**")       # Count
    add("")

    # --- Summary table by type ------------------------------------------------
    add("## 📊 Summary by Resource Type")
    add("")
    add("| Resource Type | Label | Count |")                       # Table header
    add("|---|---|---:|")                                          # Alignment row
    counts: Dict[str, int] = {}                                    # type -> count
    for r in resources:                                            # Tally each type
        counts[r["type"]] = counts.get(r["type"], 0) + 1
    for rtype, n in sorted(counts.items()):                        # Sorted for stable output
        label = RECIPES.get(rtype, GENERIC_RECIPE)["label"]       # Friendly label
        add(f"| `{rtype}` | {label} | {n} |")                     # Table row
    add("")

    # --- Inventory table ------------------------------------------------------
    add("## 📋 Resource Inventory")
    add("")
    add("| # | Name | Type | AWS ID | Terraform Address |")
    add("|---:|---|---|---|---|")
    for i, r in enumerate(resources, 1):                           # Number each resource
        recipe = RECIPES.get(r["type"], GENERIC_RECIPE)           # Look up recipe
        add(f"| {i} | {md_escape(resource_name(r))} | `{r['type']}` | "
            f"`{md_escape(resource_id(r, recipe))}` | `{md_escape(r.get('address', ''))}` |")
    add("")

    # --- Detailed section per resource ---------------------------------------
    add("## 🔍 Resource Details")
    add("")
    for i, r in enumerate(resources, 1):                           # One sub-section per resource
        recipe = RECIPES.get(r["type"], GENERIC_RECIPE)           # Recipe for this type
        ctx = build_context(r, recipe, region)                     # Placeholder values
        add(f"### {i}. {recipe['label']} — `{resource_name(r)}`")  # Sub-heading
        add("")
        add(f"- **Terraform address:** `{r.get('address', '')}`")  # Where it lives in TF
        add(f"- **Type:** `{r['type']}`")                          # Provider type
        add(f"- **AWS ID:** `{ctx['id']}`")                        # Identifier
        add("")
        attrs = key_attributes(r)                                  # Interesting attributes
        if attrs:                                                  # Only draw table if any exist
            add("| Attribute | Value |")
            add("|---|---|")
            for k, v in attrs.items():                             # One row per attribute
                add(f"| `{k}` | `{md_escape(v)}` |")
            add("")
        add("**👀 View with AWS CLI**")                            # View commands block
        add("")
        add("```bash")
        for cmd in recipe["view"]:                                 # Fill each template
            add(fill(cmd, ctx))
        add("```")
        add("")
        add("**💣 Destroy with AWS CLI**")                         # Destroy commands block
        add("")
        add("```bash")
        for cmd in recipe["destroy"]:                              # Fill each template
            add(fill(cmd, ctx))
        add("```")
        add("")

    # --- Terraform outputs (optional) -----------------------------------------
    if outputs:                                                    # Only if --outputs was given
        add("## 📤 Terraform Outputs")
        add("")
        add("| Output | Value | Sensitive |")
        add("|---|---|---|")
        for name, meta in outputs.items():                         # Each output entry
            sensitive = meta.get("sensitive", False)               # Hide secret values
            value = "***" if sensitive else json.dumps(meta.get("value"))   # Mask if sensitive
            add(f"| `{name}` | `{md_escape(value)}` | {'✅' if sensitive else '—'} |")
        add("")

    # --- Consolidated scripts --------------------------------------------------
    add("## 🧾 All VIEW Commands (copy/paste)")
    add("")
    add("```bash")
    for r in resources:                                            # Every resource, in order
        recipe = RECIPES.get(r["type"], GENERIC_RECIPE)
        ctx = build_context(r, recipe, region)
        add(f"# {r.get('address', '')}")                           # Comment showing the address
        for cmd in recipe["view"]:
            add(fill(cmd, ctx))
    add("```")
    add("")
    add("## 🔥 All DESTROY Commands (reverse dependency order)")
    add("")
    add("> ⚠️ **Warning:** these commands are irreversible. Prefer `terraform destroy` where possible; "
        "use these only if the Terraform state is lost or corrupted.")
    add("")
    add("```bash")
    for r in reversed(resources):                                  # Reverse order ≈ safe teardown
        recipe = RECIPES.get(r["type"], GENERIC_RECIPE)
        ctx = build_context(r, recipe, region)
        add(f"# {r.get('address', '')}")
        for cmd in recipe["destroy"]:
            add(fill(cmd, ctx))
    add("```")
    add("")
    add("---")
    add("*Report generated by `terraform_report.py`.*")             # Footer
    return "\n".join(lines) + "\n"                                 # Join into one string


# ----------------------------------------------------------------------------
# 4. Command-line entry point
# ----------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    """Define and parse the command-line interface."""
    p = argparse.ArgumentParser(                                   # Create the parser
        description="Turn `terraform show -json` output into a Markdown report with AWS CLI commands."
    )
    p.add_argument("state_json", type=Path,                        # Required positional argument
                   help="Path to output of `terraform show -json` (state or plan).")
    p.add_argument("--outputs", type=Path, default=None,           # Optional outputs file
                   help="Path to output of `terraform output -json`.")
    p.add_argument("--region", default="us-east-1",                # Default AWS region
                   help="Region used in CLI commands when not present in state (default: us-east-1).")
    p.add_argument("--out", type=Path, default=Path("TERRAFORM_REPORT.md"),   # Output file
                   help="Where to write the Markdown report (default: TERRAFORM_REPORT.md).")
    return p.parse_args()                                          # Parse sys.argv


def main() -> None:
    """Orchestrate: load -> filter -> render -> write."""
    args = parse_args()                                            # Read CLI flags
    tf_json = load_json(args.state_json)                           # Load the Terraform JSON
    resources = only_managed_aws(extract_resources(tf_json))       # Get only AWS managed resources
    outputs = load_json(args.outputs) if args.outputs else None    # Load outputs if provided
    report = render_report(resources, outputs, args.region, str(args.state_json))   # Build Markdown
    args.out.write_text(report, encoding="utf-8")                  # Save to disk
    print(f"✅ Report written to {args.out} ({len(resources)} AWS resources)")   # Confirm to user


if __name__ == "__main__":                                         # Only run when executed directly
    main()                                                         # Kick off the program
