# Architecture

## Overview

This project implements a fully serverless, event-driven security 
auto-remediation pipeline on AWS. When a threat is detected, the pipeline 
moves from detection to remediation in under 10 seconds with no human 
intervention required. The architecture is aligned with FedRAMP and NIST 
800-53 security controls.

No servers run continuously. No polling loops exist. Every component is 
idle and costs nothing until a finding arrives.

## Pipeline Tiers

### Tier 1 Detection

In a production deployment, Amazon GuardDuty continuously ingests three 
data sources:

- **AWS CloudTrail**  every API call made in the account
- **VPC Flow Logs**  all network traffic metadata
- **DNS Logs**  domain resolution requests from within the VPC

GuardDuty's ML models analyze these sources against a continuously updated 
threat intelligence feed and behavioral baseline for the account. When 
anomalous activity is detected, GuardDuty generates a finding with a 
severity score between 0.1 and 10.0.

In this implementation, GuardDuty is replaced by direct EventBridge event 
injection using the AWS CLI. The mock payloads use the exact GuardDuty 
finding schema, so the entire downstream pipeline behaves identically to 
a live deployment. Swapping in a real GuardDuty detector requires no 
changes to any other component.

### Tier 2 Event Routing

An EventBridge rule evaluates every incoming event against three 
conditions simultaneously:

- `source` must equal `aws.guardduty`
- `detail-type` must equal `GuardDuty Finding`  
- `detail.severity` must be numerically >= 4.0

### Tier 3 Fan-Out

The SNS topic receives matched findings from EventBridge and delivers 
them to all subscribers in parallel. Key properties:

- Encrypted at rest using an AWS-managed SSE key
- A Dead-Letter Queue captures any messages that fail delivery after 
  SNS exhausts its retry policy
- Topic policy restricts publishing rights exclusively to the 
  EventBridge service identity

### Tier 4 Auto-Remediation Lambdas

Four Lambda functions subscribe to the SNS topic. Each 
has its own least-privilege IAM execution role and handles a specific 
class of misconfiguration:

**IAM Revoke** `NIST AC-2, AC-6`  
Triggers on credential-based findings. Disables the compromised IAM 
access key by setting its status to Inactive. The key is not deleted 
preserving it allows forensic investigation of what actions were taken 
with it before compromise was detected.

**SG Lockdown** `NIST CM-7, SC-7`  
Triggers on port probe and network exposure findings. Identifies ingress 
rules permitting traffic from `0.0.0.0/0` or `::/0` and revokes them. 
Handles both IPv4 and IPv6 open rules

**EC2 Isolate** `NIST IR-4, SI-4`  
Triggers on instance compromise findings. Creates a new quarantine 
security group with zero ingress and zero egress rules in the instance's 
VPC, then moves the instance into it. The instance remains running for 
forensic analysis but is completely network-isolated. The original 
security groups are preserved, not modified, to maintain evidence of 
the pre-compromise network configuration. The instance is tagged with 
quarantine metadata including the finding ID and timestamp.

**S3 Block Public** `NIST AC-3, SC-28`  
Triggers on public bucket findings. Enforces all four S3 public access 
block settings simultaneously. Additionally reads the existing bucket 
policy and surgically removes only statements that grant public access, 
preserving any legitimate role-based or service-based policy statements 
that should remain.

### Tier 5 Audit, Notify, Verify

**AWS Security Hub**  
Each Lambda calls `update_findings` after remediation, marking the 
finding as ARCHIVED with a timestamped note. Security Hub maps every 
resolved finding to its NIST 800-53 control family automatically, 
generating a continuous compliance evidence trail.

**CloudWatch Logs and Metrics**  
Every Lambda emits structured JSON logs containing an `mttr_seconds` 
field. A CloudWatch metric filter watches the log stream in real time, 
extracts that value, and publishes it as a custom metric in the 
`GuardDuty/AutoRemediation` namespace. A CloudWatch alarm fires if the 
maximum MTTR in any 5-minute window exceeds 30 seconds, delivering 
notification via the ops SNS topic.

**SNS Ops Alert**  
A separate SNS topic from the remediation pipeline carries human-readable 
notifications about pipeline health MTTR threshold breaches, alarm 
state changes, and recovery notifications. Subscribers can include email, 
PagerDuty, or Slack webhook endpoints.

### Tier 6 Compliance Persistence

**AWS Config**  
Continuously records configuration changes to IAM users, EC2 security 
groups, and S3 buckets exactly the resource types the four Lambda 
functions remediate. Two managed Config rules run continuously:

- `INCOMING_SSH_DISABLED`  verifies no security group permits port 22 
  from `0.0.0.0/0`
- `S3_BUCKET_PUBLIC_ACCESS_PROHIBITED`  verifies all S3 buckets have 
  public access blocks enforced

If a remediation is manually reverted, Config detects the drift on the 
next evaluation cycle and marks the resource NON_COMPLIANT. In a 
production deployment this NON_COMPLIANT event would be wired back into 
EventBridge to trigger re-remediation automatically.

**S3 Audit Bucket**  
All Config snapshots and Lambda execution logs are archived to a 
dedicated S3 bucket with versioning enabled, AES256 encryption at rest, 
and all four public access block settings enforced. Versioning provides 
tamper-evidence overwritten or deleted objects retain their version 
history. A lifecycle rule expires current object versions after 90 days 
and cleans up non-current versions after 30 days.

---

## Production Considerations

This implementation is optimized for free-tier deployment and 
demonstration purposes. A production or FedRAMP-authorized deployment 
would incorporate the following changes:

| Component | Demo Configuration | Production Configuration |
|-----------|-------------------|--------------------------|
| GuardDuty | Mock CLI injection | Live detector with S3, EKS, and Malware Protection enabled |
| KMS | AWS-managed keys (alias/aws/sns) | Customer-managed keys with explicit key policies and rotation |
| S3 Object Lock | Versioning only | COMPLIANCE mode, 365-day retention |
| CloudWatch retention | 1 day | 90+ days per NIST AU-11 |
| Config recording | 3 resource types | All supported resource types |
| SNS encryption | SSE-SQS | CMK with role-scoped key policy |
| Lambda concurrency | Unreserved | Reserved concurrency per function |

---