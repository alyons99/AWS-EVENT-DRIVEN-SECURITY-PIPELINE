# AWS GuardDuty Auto-Remediation Pipeline

## What This Builds
Autoremediation pipeline that detects for types of attacks/misconfigurations and autoremediates
1. Unauthorized EC2 access
2. Unauthorized IAM access
3. Closes unprotected ports
4. Block public S3 access

With the goal of hitting near zero mean-time-to-repair (MTTR)

## Pipeline Flow
EventBridge → SNS → Lambda (x4 parallel) → CloudWatch → Security Hub

## Prerequisites
- AWS account (free tier)
- AWS CLI v2
- Terraform >= 1.6

## Quick Start
1. Clone the repo
2. cp terraform/terraform.tfvars.example terraform/terraform.tfvars
3. Fill in your values
4. terraform init && terraform apply
5. Confirm the SNS email subscription
6. aws events put-events --entries file://test-events/inject-iam.json
7. Check CloudWatch Logs for results

## NIST 800-53 Control Mapping
See nist.md in docs/

## Architecture
See architecture.md in docs/

## Cost
$0 — fully free tier.

## Production Considerations
- Replace AWS-managed KMS keys with CMKs
- Enable GuardDuty detector to replace mock injection
- Set S3 Object Lock for immutable audit logs
- Increase CloudWatch log retention beyond 1 day
