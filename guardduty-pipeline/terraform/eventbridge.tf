resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-medium-plus"
  description = "Route GuardDuty findings severity >= 4.0 (MEDIUM+)"
#looking for events on the bus that come from guard duty
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
#making sure those guard duty events are the right type of event, a finding
    detail-type = ["GuardDuty Finding"]
    detail = {
#we only want events GuardDuty rates as greater than a 4
      severity = [{ numeric = [">=", 4.0] }]
    }
  })
}

#arn will be passed over to SNS for subscribing lambda functions
resource "aws_cloudwatch_event_target" "to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.remediation.arn
}