# S3 File Mover (SQS → Lambda, private network)

```
send_message Lambda ──► SQS queue ──► move_file Lambda ──► S3 copy + delete
   (event)                (DLQ)        (private subnets)    reports/sales.csv
                                                            → reports/sales_20260907.csv
```

Everything runs in private subnets with **no NAT or internet gateway**:
- S3 traffic goes through a **Gateway VPC endpoint**
- SQS traffic goes through an **Interface VPC endpoint** (private DNS on)
- The queue policy **denies `SendMessage` from anywhere except that endpoint**
- Both buckets block public access and are encrypted at rest

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | SAM/CloudFormation: buckets, queue + DLQ, VPC endpoints, both Lambdas |
| `move_file/app.py` | SQS consumer: copies to destination with dated name, deletes source |
| `send_message/app.py` | Simple event Lambda that publishes the move request to SQS |

## Message format

```json
{
  "file_name": "reports/sales.csv",
  "source_bucket": "my-source-bucket",
  "destination_bucket": "my-destination-bucket"
}
```

The date is inserted before the extension: `sales.csv` → `sales_20260907.csv`.
Change `DATE_FORMAT` in the template (e.g. `%y%m%d` for `260907`, `%Y-%m-%d` for `2026-09-07`).

## Deploy

Prerequisites: AWS SAM CLI, an existing VPC with private subnets.

```bash
sam build
sam deploy --guided \
  --parameter-overrides \
    VpcId=vpc-0123456789abcdef0 \
    PrivateSubnetIds=subnet-aaa,subnet-bbb \
    PrivateRouteTableIds=rtb-aaa,rtb-bbb \
    SourceBucketName=my-source-bucket \
    DestinationBucketName=my-destination-bucket
```

## Test

```bash
# 1. put a file in the source bucket
echo "hello" > sales.csv
aws s3 cp sales.csv s3://my-source-bucket/reports/sales.csv

# 2. fire the sender Lambda (it puts the message on SQS)
aws lambda invoke --function-name <stack>-send-message \
  --cli-binary-format raw-in-base64-out \
  --payload '{"file_name":"reports/sales.csv","source_bucket":"my-source-bucket","destination_bucket":"my-destination-bucket"}' \
  out.json

# 3. verify
aws s3 ls s3://my-destination-bucket/reports/   # sales_20260907.csv
aws s3 ls s3://my-source-bucket/reports/        # empty
```

To run it on a schedule instead, set `State: ENABLED` on `NightlySchedule` in the template; it uses the `DEFAULT_FILE_NAME` / bucket env vars when the event is empty.

## Error handling

- Bad JSON / missing fields → logged and dropped (retrying wouldn't help).
- AWS errors (missing object, permissions, throttling) → reported via `ReportBatchItemFailures`, so only that message is retried; after 3 attempts it lands in the DLQ.
- Queue `VisibilityTimeout` (360 s) is 6× the Lambda timeout, as AWS recommends.

## Notes

- `copy_object` works for objects up to 5 GB. For larger files, swap it for `boto3.client("s3").copy(...)` (managed multipart transfer); the IAM policy is already sufficient.
- If you want to lock the buckets to the VPC as well, add a bucket policy with `Deny` + `aws:SourceVpce != <S3GatewayEndpoint>`, but note that will also block console/CLI access from outside the VPC.
