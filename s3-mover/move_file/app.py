"""
SQS-triggered Lambda: moves a file from one S3 bucket to another,
inserting a short date (YYYYMMDD) before the file extension.

Expected SQS message body (JSON):
{
  "file_name": "reports/sales.csv",
  "source_bucket": "my-source-bucket",
  "destination_bucket": "my-destination-bucket"
}

Result: my-destination-bucket/reports/sales_20260907.csv
"""
import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
DATE_FORMAT = os.environ.get("DATE_FORMAT", "%Y%m%d")


def build_dated_key(key: str) -> str:
    """reports/sales.csv -> reports/sales_20260907.csv"""
    today = datetime.now(timezone.utc).strftime(DATE_FORMAT)
    folder, _, name = key.rpartition("/")
    base, dot, ext = name.rpartition(".")
    if not dot:  # no extension
        new_name = f"{name}_{today}"
    else:
        new_name = f"{base}_{today}.{ext}"
    return f"{folder}/{new_name}" if folder else new_name


def move_object(source_bucket: str, key: str, destination_bucket: str) -> str:
    new_key = build_dated_key(key)
    logger.info("Copying s3://%s/%s -> s3://%s/%s", source_bucket, key, destination_bucket, new_key)
    s3.copy_object(
        Bucket=destination_bucket,
        Key=new_key,
        CopySource={"Bucket": source_bucket, "Key": key},
    )
    s3.delete_object(Bucket=source_bucket, Key=key)
    logger.info("Deleted original s3://%s/%s", source_bucket, key)
    return new_key


def handler(event, context):
    failures = []  # partial batch failure reporting

    for record in event.get("Records", []):
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            key = body["file_name"]
            src = body["source_bucket"]
            dst = body["destination_bucket"]
            new_key = move_object(src, key, dst)
            logger.info("Message %s done: %s", message_id, new_key)
        except (KeyError, json.JSONDecodeError) as exc:
            # Malformed message: retrying will never help, log and drop it.
            logger.error("Message %s malformed, dropping: %s", message_id, exc)
        except ClientError as exc:
            # Transient/AWS error: report failure so SQS retries only this message.
            logger.exception("Message %s failed: %s", message_id, exc)
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}
