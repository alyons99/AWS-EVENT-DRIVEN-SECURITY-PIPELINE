#S3 bucket for audit logs, appending aws account id enforces unique global naming
#We want to delete the bucket even if it contains objects for force_destory = true
resource "aws_s3_bucket" "audit_logs" {
  bucket        = "guardduty-audit-${var.aws_account_id}"
  force_destroy = true
}

#We want versioning turned on in our bucket
resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

#Encryption at rest using S3 managed keys
#In prod, we would use CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#Block all public access to bucker and prevent access
#Blocks policy attachement as an alternate form of access
resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#Expire old logs after 90 days
#Expire old versions after 30
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

#Config service role
resource "aws_iam_role" "config_role" {
  name               = "guardduty-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_role" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
#Config recorder scoped to our remediations (IAM, EC2, and S3)
resource "aws_config_configuration_recorder" "main" {
  name     = "guardduty-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported  = false
    resource_types = [
      "AWS::IAM::User",
      "AWS::EC2::SecurityGroup",
      "AWS::S3::Bucket"
    ]
  }
}
#Config writes to the S3 audit bucket we defined
resource "aws_config_delivery_channel" "main" {
  name           = "guardduty-delivery"
  s3_bucket_name = aws_s3_bucket.audit_logs.bucket
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

#Subscriping to pre-defined config rules, no need for custom at this time
resource "aws_config_config_rule" "no_open_ssh" {
  name       = "restricted-ssh"
  depends_on = [aws_config_configuration_recorder.main]

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

resource "aws_config_config_rule" "s3_no_public" {
  name       = "s3-bucket-public-access-prohibited"
  depends_on = [aws_config_configuration_recorder.main]

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }
}