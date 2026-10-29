variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform state"
}
