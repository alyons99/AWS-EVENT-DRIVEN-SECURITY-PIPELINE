output "sns_topic_arn" {
  description = "ARN of the GuardDuty remediation SNS topic"
  value       = aws_sns_topic.remediation.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge finding filter rule"
  value       = aws_cloudwatch_event_rule.guardduty_findings.arn
}

output "lambda_function_arns" {
  description = "ARNs of all four remediation Lambda functions"
  value = {
    iam_revoke = aws_lambda_function.iam_revoke.arn
    sg_lockdown = aws_lambda_function.sg_lockdown.arn
    ec2_isolate = aws_lambda_function.ec2_isolate.arn
    s3_block    = aws_lambda_function.s3_block.arn
  }
}

output "audit_bucket_name" {
  description = "Name of the S3 audit log bucket"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "inject_command" {
  description = "CLI command to inject a mock GuardDuty finding"
  value       = "aws events put-events --entries file://test-events/inject-iam.json"
}