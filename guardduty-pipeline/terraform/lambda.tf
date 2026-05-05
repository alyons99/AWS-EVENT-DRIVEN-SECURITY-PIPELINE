#AWS needs zip files under lambda/ and to place it in builds/
data "archive_file" "iam_revoke" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/iam_revoke"
  output_path = "${path.module}/builds/iam_revoke.zip"
}

data "archive_file" "sg_lockdown" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/sg_lockdown"
  output_path = "${path.module}/builds/sg_lockdown.zip"
}

data "archive_file" "ec2_isolate" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ec2_isolate"
  output_path = "${path.module}/builds/ec2_isolate.zip"
}

data "archive_file" "s3_block" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/s3_block"
  output_path = "${path.module}/builds/s3_block.zip"
}

#lambda function definitions
#I chose a 30s timeout as functions only make a few API calls
#128MB is the min compute, they just make API calls and parse JSON from guardduty

#IAM Revoke Function
resource "aws_lambda_function" "iam_revoke" {
  filename         = data.archive_file.iam_revoke.output_path
  function_name    = "guardduty-iam-revoke"
  role             = aws_iam_role.iam_revoke.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.iam_revoke.output_base64sha256
#x-ray tracing for loggin and troubleshooting purposes
  environment {
    variables = { LOG_LEVEL = "INFO" }
  }

  tracing_config { mode = "Active" }
}

#Security Group Lockdown Function
resource "aws_lambda_function" "sg_lockdown" {
  filename         = data.archive_file.sg_lockdown.output_path
  function_name    = "guardduty-sg-lockdown"
  role             = aws_iam_role.sg_lockdown.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.sg_lockdown.output_base64sha256

  environment {
    variables = { LOG_LEVEL = "INFO" }
  }

  tracing_config { mode = "Active" }
}

#EC2 Isolate Function
resource "aws_lambda_function" "ec2_isolate" {
  filename         = data.archive_file.ec2_isolate.output_path
  function_name    = "guardduty-ec2-isolate"
  role             = aws_iam_role.ec2_isolate.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.ec2_isolate.output_base64sha256

  environment {
    variables = { LOG_LEVEL = "INFO" }
  }

  tracing_config { mode = "Active" }
}

#S3 Block Public Access Function
resource "aws_lambda_function" "s3_block" {
  filename         = data.archive_file.s3_block.output_path
  function_name    = "guardduty-s3-block"
  role             = aws_iam_role.s3_block.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.s3_block.output_base64sha256

  environment {
    variables = { LOG_LEVEL = "INFO" }
  }

  tracing_config { mode = "Active" }
}

#Using a fan-out model with SNS, all subscribers receive messages at the same time
resource "aws_sns_topic_subscription" "iam_revoke" {
  topic_arn = aws_sns_topic.remediation.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.iam_revoke.arn
}

resource "aws_sns_topic_subscription" "sg_lockdown" {
  topic_arn = aws_sns_topic.remediation.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sg_lockdown.arn
}

resource "aws_sns_topic_subscription" "ec2_isolate" {
  topic_arn = aws_sns_topic.remediation.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ec2_isolate.arn
}

resource "aws_sns_topic_subscription" "s3_block" {
  topic_arn = aws_sns_topic.remediation.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.s3_block.arn
}

#Giving SNS permissions to invoke lambda functions
#Again using the principal of least permissions
resource "aws_lambda_permission" "iam_revoke_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_revoke.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.remediation.arn
}

resource "aws_lambda_permission" "sg_lockdown_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sg_lockdown.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.remediation.arn
}

resource "aws_lambda_permission" "ec2_isolate_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_isolate.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.remediation.arn
}

resource "aws_lambda_permission" "s3_block_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_block.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.remediation.arn
}