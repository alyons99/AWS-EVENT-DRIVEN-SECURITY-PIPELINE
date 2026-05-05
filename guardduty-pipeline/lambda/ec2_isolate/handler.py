import boto3
import json
import logging
from datetime import datetime, timezone

log = logging.getLogger()
log.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sh  = boto3.client("securityhub")

def lambda_handler(event, context):
    #Parses the SNS events
    message    = json.loads(event["Records"][0]["Sns"]["Message"])
    finding    = message["detail"]
    account_id = finding["accountId"]
    region     = finding["region"]
    start      = datetime.now(timezone.utc)

    #Extract instance ID
    try:
        instance_id = finding["resource"]["instanceDetails"]["instanceId"]
    except KeyError:
        log.warning(json.dumps({
            "action"     : "ec2_isolate",
            "status"     : "skipped",
            "reason"     : "no instance ID in finding",
            "finding_id" : finding["id"]
        }))
        return {"status": "skipped"}

    #Get instance VPC
    instance = ec2.describe_instances(
        InstanceIds=[instance_id]
    )["Reservations"][0]["Instances"][0]
    vpc_id = instance["VpcId"]

    #Create quarantined security group
    # No ingress or egress
    quarantine_sg = ec2.create_security_group(
        GroupName   = f"quarantine-{instance_id}",
        Description = f"Quarantine SG for compromised instance {instance_id}",
        VpcId       = vpc_id
    )
    quarantine_sg_id = quarantine_sg["GroupId"]

    #Remove the default outbound allow-all rule AWS adds automatically
    ec2.revoke_security_group_egress(
        GroupId = quarantine_sg_id,
        IpPermissions = [{
            "IpProtocol": "-1",
            "IpRanges"  : [{"CidrIp": "0.0.0.0/0"}]
        }]
    )

    #Swap instance into quarantine SG
    ec2.modify_instance_attribute(
        InstanceId     = instance_id,
        Groups         = [quarantine_sg_id]
    )

    #Tag instance as quarantined
    ec2.create_tags(
        Resources = [instance_id],
        Tags = [
            {"Key": "QuarantineStatus",  "Value": "Isolated"},
            {"Key": "QuarantineReason",  "Value": finding["type"]},
            {"Key": "QuarantineTime",    "Value": datetime.now(timezone.utc).isoformat()},
            {"Key": "FindingId",         "Value": finding["id"]}
        ]
    )

    #Capture the mttr
    mttr = (datetime.now(timezone.utc) - start).total_seconds()

    #Create a json log with info and mttr
    log.info(json.dumps({
        "action"          : "ec2_isolate",
        "status"          : "remediated",
        "instance_id"     : instance_id,
        "quarantine_sg_id": quarantine_sg_id,
        "vpc_id"          : vpc_id,
        "mttr_seconds"    : mttr,
        "finding_id"      : finding["id"]
    }))

    #Resolve finding in Security Hub
    sh.update_findings(
        Filters     = {"Id": [{"Value": finding["id"], "Comparison": "EQUALS"}]},
        Note        = {"Text": f"Instance {instance_id} isolated in {mttr:.1f}s",
                       "UpdatedBy": "lambda"},
        RecordState = "ARCHIVED"
    )

    return {
        "status"          : "remediated",
        "instance_id"     : instance_id,
        "quarantine_sg_id": quarantine_sg_id,
        "mttr_seconds"    : mttr
    }