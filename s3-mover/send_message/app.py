"""
Simple event Lambda: publishes a "move file" request to the SQS queue.

Invoke with an event like:
{
  "file_name": "reports/sales.csv",
  "source_bucket": "my-source-bucket",
  "destination_bucket": "my-destination-bucket"
}

Any missing field falls back to the environment defaults set in template.yaml,
so an EventBridge schedule can invoke it with an empty event.
"""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["QUEUE_URL"]


def handler(event, context):
    event = event or {}
    message = {
        "file_name": event.get("file_name", os.environ.get("DEFAULT_FILE_NAME")),
        "source_bucket": event.get("source_bucket", os.environ.get("SOURCE_BUCKET")),
        "destination_bucket": event.get("destination_bucket", os.environ.get("DESTINATION_BUCKET")),
    }

    missing = [k for k, v in message.items() if not v]
    if missing:
        raise ValueError(f"Missing required fields: {missing}")

    resp = sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(message))
    logger.info("Sent message %s: %s", resp["MessageId"], message)
    return {"messageId": resp["MessageId"], "message": message}
