#Shared Lambda trust policy for lambda to assume
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

#lambda_common covers logging and securityHub
data "aws_iam_policy_document" "lambda_common" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["securityhub:UpdateFindings"]
    resources = ["*"]
  }
}

#I created roles for each remediation lambda to comply with least priviledge via isolation

#IAM Revoke role
resource "aws_iam_role" "iam_revoke" {
  name               = "lambda-guardduty-iam-revoke"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}
resource "aws_iam_role_policy" "iam_revoke_common" {
  role   = aws_iam_role.iam_revoke.id
  policy = data.aws_iam_policy_document.lambda_common.json
}
resource "aws_iam_role_policy" "iam_revoke_specific" {
  role   = aws_iam_role.iam_revoke.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:UpdateAccessKey","iam:ListAccessKeys","iam:TagUser"]
      Resource = "*"
    }]
  })
}

#Security Group Lockdown role
resource "aws_iam_role" "sg_lockdown" {
  name               = "lambda-guardduty-sg-lockdown"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}
resource "aws_iam_role_policy" "sg_lockdown_common" {
  role   = aws_iam_role.sg_lockdown.id
  policy = data.aws_iam_policy_document.lambda_common.json
}
resource "aws_iam_role_policy" "sg_lockdown_specific" {
  role   = aws_iam_role.sg_lockdown.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeSecurityGroups","ec2:RevokeSecurityGroupIngress"]
      Resource = "*"
    }]
  })
}

#EC2 Isolate role
resource "aws_iam_role" "ec2_isolate" {
  name               = "lambda-guardduty-ec2-isolate"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}
resource "aws_iam_role_policy" "ec2_isolate_common" {
  role   = aws_iam_role.ec2_isolate.id
  policy = data.aws_iam_policy_document.lambda_common.json
}
resource "aws_iam_role_policy" "ec2_isolate_specific" {
  role   = aws_iam_role.ec2_isolate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances","ec2:ModifyInstanceAttribute",
                  "ec2:CreateSecurityGroup","ec2:AuthorizeSecurityGroupIngress"]
      Resource = "*"
    }]
  })
}

#S3 Block Public Access role
resource "aws_iam_role" "s3_block" {
  name               = "lambda-guardduty-s3-block"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}
resource "aws_iam_role_policy" "s3_block_common" {
  role   = aws_iam_role.s3_block.id
  policy = data.aws_iam_policy_document.lambda_
}
resource "aws_iam_role_policy" "s3_block_specific" {
  role   = aws_iam_role.s3_block.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutPublicAccessBlock","s3:PutBucketPolicy","s3:GetBucketPolicy"]
      Resource = "*"
    }]
  })
}