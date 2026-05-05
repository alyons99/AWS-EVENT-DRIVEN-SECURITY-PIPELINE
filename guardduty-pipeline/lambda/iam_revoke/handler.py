import boto3
import json
import logging
from datetime import datetime, timezone

log = logging.getLogger()
log.setLevel(logging.INFO)

iam = boto3.client("iam")
sh  = boto3.client("securityhub")

def lambda_handler(event, context):
    #Parses the SNS events
    message = json.loads(event["Records"][0]["Sns"]["Message"])
    finding = message["detail"]
    
    user   = finding["resource"]["accessKeyDetails"]["userName"]
    key_id = finding["resource"]["accessKeyDetails"]["accessKeyId"]
    start  = datetime.now(timezone.utc)

    #Remediation
    #Try to set the user to inactive
    try:
        iam.update_access_key(
            UserName    = user,
            AccessKeyId = key_id,
            Status      = "Inactive"
        )
        status = "remediated"
    except iam.exceptions.NoSuchEntityException:
        #Error handling for key already disabled or not found
        status = "skipped"
        log.warning(json.dumps({
            "action"     : "iam_key_disabled",
            "status"     : "skipped",
            "reason"     : "key not found",
            "key_id"     : key_id,
            "finding_id" : finding["id"]
        }))
        return {"status": status}

    #Capture the mttr
    mttr = (datetime.now(timezone.utc) - start).total_seconds()

    #Create a json log with info and mttr
    log.info(json.dumps({
        "action"      : "iam_key_disabled",
        "status"      : status,
        "key_id"      : key_id,
        "user"        : user,
        "mttr_seconds": mttr,
        "finding_id"  : finding["id"]
    }))

    #Resolve finding in Security Hub
    sh.update_findings(
        Filters  = {"Id": [{"Value": finding["id"], "Comparison": "EQUALS"}]},
        Note     = {"Text": f"Auto-remediated in {mttr:.1f}s", "UpdatedBy": "lambda"},
        RecordState = "ARCHIVED"
    )

    return {"status": status, "mttr_seconds": mttr}