#We want control over the retention period, so I chose to define the log group
#Otherwise, they will retain indefinetely
resource "aws_cloudwatch_log_group" "lambdas" {
  for_each          = toset(["iam-revoke","sg-lockdown","ec2-isolate","s3-block"])
  name              = "/aws/lambda/guardduty-${each.key}"
  retention_in_days = 1
}

#Capturing a MMTR metric using a filter for CloudWatch
resource "aws_cloudwatch_log_metric_filter" "mttr" {
  name           = "remediation-mttr"
  log_group_name = "/aws/lambda/guardduty-iam-revoke"
  pattern        = "{ $.mttr_seconds > 0 }"

  metric_transformation {
    name          = "RemediationMTTR"
    namespace     = "GuardDuty/AutoRemediation"
    value         = "$.mttr_seconds"
    unit          = "Seconds"
    default_value = "0"
  }
}

#Error handling and setting a default value of 0
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "remediation-errors"
  log_group_name = "/aws/lambda/guardduty-iam-revoke"
  pattern        = "{ $.status = \"error\" }"

  metric_transformation {
    name          = "RemediationErrors"
    namespace     = "GuardDuty/AutoRemediation"
    value         = "1"
    default_value = "0"
  }
}

#Alarm goes off if remediation takes more than 30s
resource "aws_cloudwatch_metric_alarm" "mttr_high" {
  alarm_name          = "guardduty-mttr-exceeded"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RemediationMTTR"
  namespace           = "GuardDuty/AutoRemediation"
  period              = 300
  statistic           = "Maximum"
  threshold           = 30
  alarm_description   = "Remediation MTTR exceeded 30s threshold"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
}

#Ops email SNS notification
resource "aws_sns_topic" "ops_alerts" {
  name              = "guardduty-ops-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "ops_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.ops_email
}