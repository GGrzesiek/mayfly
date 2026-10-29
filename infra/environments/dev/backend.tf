terraform {
  # 1.10 is the first release with S3-native state locking (use_lockfile).
  required_version = ">= 1.10.0"
  backend "s3" {
    bucket  = "mayfly-tfstate-0852fa70"
    key     = "dev/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
    # The lock is a <key>.tflock object next to the state, so the bucket is
    # the only backend resource. Replaces the DynamoDB table, which
    # Terraform has deprecated for this purpose.
    use_lockfile = true
  }
}
