variable "aws_region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "ops_email" {
  description = "Email address to receive ops alerts and SNS subscription confirmation"
  type        = string
}

variable "aws_account_id" {
  description = "Your AWS account ID - used for constructing ARNs"
  type        = string
}