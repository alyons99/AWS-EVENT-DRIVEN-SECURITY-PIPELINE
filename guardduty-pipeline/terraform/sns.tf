# Using AWS-managed key (alias/aws/sns) for demo simplicity.
# Production / FedRAMP deployment should use a customer-managed KMS keys (CMK)
resource "aws_sns_topic" "remediation" {
  name              = "guardduty-auto-remediation"
  kms_master_key_id = "alias/aws/sns"
}


resource "aws_sns_topic_policy" "remediation" {
  arn    = aws_sns_topic.remediation.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

#we only want events coming from EventBridge to be published to this topic
data "aws_iam_policy_document" "sns_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions    = ["SNS:Publish"]
    resources  = [aws_sns_topic.remediation.arn]
  }
}
#dead letter queue will catch messages that fail to process properly
#holds for 14 days for analysis and manual remediation
#in prod, pushing these to S3 might be good for long term analysis
resource "aws_sqs_queue" "dlq" {
  name                      = "guardduty-remediation-dlq"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 604800
}

resource "aws_sns_topic_subscription" "dlq_sub" {
  topic_arn = aws_sns_topic.remediation.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.dlq.arn
}