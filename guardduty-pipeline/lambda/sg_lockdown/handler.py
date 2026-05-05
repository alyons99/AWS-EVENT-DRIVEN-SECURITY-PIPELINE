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
    message = json.loads(event["Records"][0]["Sns"]["Message"])
    finding = message["detail"]
    start   = datetime.now(timezone.utc)

    #Extract security group ID
    try:
        sg_id = (finding["resource"]["instanceDetails"]
                 ["networkInterfaces"][0]["securityGroups"][0]["groupId"])
    except (KeyError, IndexError):
        log.warning(json.dumps({
            "action"     : "sg_lockdown",
            "status"     : "skipped",
            "reason"     : "no security group found in finding",
            "finding_id" : finding["id"]
        }))
        return {"status": "skipped"}

    #Find offending rules
    sg       = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
    bad_rules = [
        rule for rule in sg["IpPermissions"]
        if any(ip.get("CidrIp") == "0.0.0.0/0" for ip in rule.get("IpRanges",   []))
        or any(ip.get("CidrIpv6") == "::/0"     for ip in rule.get("Ipv6Ranges", []))
    ]

    #Remediation
    if bad_rules:
        ec2.revoke_security_group_ingress(
            GroupId       = sg_id,
            IpPermissions = bad_rules
        )
        status = "remediated"
    else:
        #Rules already removed, not an error
        status = "skipped"

    #Capture the mttr
    mttr = (datetime.now(timezone.utc) - start).total_seconds()

    #Create a json log with info and mttr
    log.info(json.dumps({
        "action"       : "sg_lockdown",
        "status"       : status,
        "sg_id"        : sg_id,
        "rules_removed": len(bad_rules),
        "mttr_seconds" : mttr,
        "finding_id"   : finding["id"]
    }))

    #Resolve finding in Security Hub
    sh.update_findings(
        Filters     = {"Id": [{"Value": finding["id"], "Comparison": "EQUALS"}]},
        Note        = {"Text": f"Auto-remediated in {mttr:.1f}s", "UpdatedBy": "lambda"},
        RecordState = "ARCHIVED"
    )

    return {"status": status, "mttr_seconds": mttr, "rules_removed": len(bad_rules)}