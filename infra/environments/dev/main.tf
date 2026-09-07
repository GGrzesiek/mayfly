terraform {
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.13" }
  }
}

provider "aws" { region = var.aws_region }

data "aws_caller_identity" "current" {}

locals {
  name = "mayfly-dev"
  tags = { Environment = "dev", Project = "mayfly" }
  azs  = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
}

module "vpc" {
  source = "../../modules/vpc"

  name            = local.name
  cidr            = "10.0.0.0/16"
  azs             = local.azs
  private_subnets = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  tags            = local.tags
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "flask-app"
  tags   = local.tags
}

module "github_oidc" {
  source      = "../../modules/github-oidc"
  github_org  = var.github_org
  github_repo = var.github_repo
  ecr_arns    = [module.ecr.repository_arn]

  state_bucket_arns = ["arn:aws:s3:::${var.state_bucket_name}", "arn:aws:s3:::${var.state_bucket_name}/*"]
  lock_table_arn    = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-locks"

  tags = local.tags
}

module "eks" {
  source             = "../../modules/eks"
  cluster_name       = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  tags               = local.tags
}

# Grant the terraform-plan CI role just enough K8s access to read Helm release
# state (stored as secrets) in the namespaces where Helm charts are deployed.
# AmazonEKSAdminPolicy scoped to these namespaces is the narrowest AWS-managed
# policy that includes secrets; view-only policies exclude secrets by default.
resource "aws_eks_access_entry" "terraform_plan" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_oidc.terraform_plan_role_arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "terraform_plan" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_oidc.terraform_plan_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["kube-system", "argocd"]
  }

  depends_on = [aws_eks_access_entry.terraform_plan]
}

output "ecr_repository_url" { value = module.ecr.repository_url }
output "github_actions_role_arn" { value = module.github_oidc.role_arn }
output "terraform_plan_role_arn" { value = module.github_oidc.terraform_plan_role_arn }
output "cluster_name" { value = module.eks.cluster_name }
output "argocd_password_cmd" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
