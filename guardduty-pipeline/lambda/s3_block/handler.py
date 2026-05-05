import boto3
import json
import logging
from datetime import datetime, timezone

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
sh = boto3.client("securityhub")

def lambda_handler(event, context):
    #Parses the SNS events
    message = json.loads(event["Records"][0]["Sns"]["Message"])
    finding = message["detail"]
    start   = datetime.now(timezone.utc)

    #Extract bucket name
    try:
        bucket_name = finding["resource"]["s3BucketDetails"][0]["name"]
    except (KeyError, IndexError):
        log.warning(json.dumps({
            "action"     : "s3_block_public",
            "status"     : "skipped",
            "reason"     : "no bucket name in finding",
            "finding_id" : finding["id"]
        }))
        return {"status": "skipped"}

    # Enforce all four public access blocks
    s3.put_public_access_block(
        Bucket = bucket_name,
        PublicAccessBlockConfiguration = {
            "BlockPublicAcls"      : True,
            "BlockPublicPolicy"    : True,
            "IgnorePublicAcls"     : True,
            "RestrictPublicBuckets": True
        }
    )

    #Remove any bucket policy granting public access
    try:
        policy = json.loads(s3.get_bucket_policy(Bucket=bucket_name)["Policy"])
        safe_statements = [
            stmt for stmt in policy["Statement"]
            if not (
                stmt.get("Effect") == "Allow" and
                stmt.get("Principal") in ("*", {"AWS": "*"})
            )
        ]
        if safe_statements:
            #Rewrite policy without public statements
            policy["Statement"] = safe_statements
            s3.put_bucket_policy(
                Bucket = bucket_name,
                Policy = json.dumps(policy)
            )
        else:
            #All statements were public so delete the policy
            s3.delete_bucket_policy(Bucket=bucket_name)

    except s3.exceptions.from_code("NoSuchBucketPolicy"):
        #No policy exists
        pass

    #Capture the mttr
    mttr = (datetime.now(timezone.utc) - start).total_seconds()

    #Create a json log with info and mttr
    log.info(json.dumps({
        "action"      : "s3_block_public",
        "status"      : "remediated",
        "bucket"      : bucket_name,
        "mttr_seconds": mttr,
        "finding_id"  : finding["id"]
    }))

    #Resolve finding in Security Hub
    sh.update_findings(
        Filters     = {"Id": [{"Value": finding["id"], "Comparison": "EQUALS"}]},
        Note        = {"Text": f"Bucket {bucket_name} blocked in {mttr:.1f}s",
                       "UpdatedBy": "lambda"},
        RecordState = "ARCHIVED"
    )

    return {"status": "remediated", "bucket": bucket_name, "mttr_seconds": mttr}