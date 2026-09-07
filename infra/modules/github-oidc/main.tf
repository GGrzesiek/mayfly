terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy for push-triggered jobs (CI): only branch pushes, not PRs
data "aws_iam_policy_document" "github_trust_push" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/master",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Trust policy for PR-triggered jobs (terraform plan): sub is "pull_request"
data "aws_iam_policy_document" "github_trust_pr" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:pull_request"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_trust_push.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_arns
  }
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  role   = aws_iam_role.github_actions.name
  policy = data.aws_iam_policy_document.ecr_push.json
}

# Separate role for Terraform plan — read-only, no ECR write
resource "aws_iam_role" "terraform_plan" {
  name               = "${var.name_prefix}-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.github_trust_pr.json
  tags               = var.tags
}

data "aws_iam_policy_document" "terraform_plan" {
  # Remote state
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = var.state_bucket_arns
  }
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.lock_table_arn]
  }
  # Read-only AWS permissions needed for terraform plan (state refresh)
  statement {
    actions = [
      "ec2:Describe*",
      "eks:Describe*", "eks:List*",
      "iam:Get*", "iam:List*",
      "ecr:Describe*", "ecr:List*", "ecr:GetLifecyclePolicy",
      "elasticloadbalancing:Describe*",
      "kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListAliases", "kms:ListResourceTags",
      "logs:DescribeLogGroups", "logs:ListTagsLogGroup", "logs:ListTagsForResource",
      "s3:GetBucketVersioning", "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock", "s3:GetBucketLocation", "s3:GetBucketLogging",
      "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketWebsite", "s3:GetBucketTagging",
      "s3:GetBucketObjectLockConfiguration", "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment", "s3:GetBucketNotification",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "terraform_plan" {
  role   = aws_iam_role.terraform_plan.name
  policy = data.aws_iam_policy_document.terraform_plan.json
}
