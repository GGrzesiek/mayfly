variable "name_prefix" {
  type        = string
  description = "Prefix for IAM role names, so they do not collide with other projects in the account"
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "ecr_arns" {
  type = list(string)
}

variable "state_bucket_arns" {
  type        = list(string)
  description = "ARNs of S3 buckets holding Terraform state (for terraform-plan role)"
}

variable "lock_file_arn" {
  type        = string
  description = "ARN of the S3 lock object next to the state (for terraform-plan role)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
