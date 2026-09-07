terraform {
  required_version = ">= 1.8.0"
  backend "s3" {
    bucket         = "mayfly-tfstate-0852fa70"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
