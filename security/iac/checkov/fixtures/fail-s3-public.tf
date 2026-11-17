# Synthetic isolated fixture for Gate G09.2 Checkov failure testing
# Deliberately insecure Terraform resource (public S3 bucket)
# DO NOT apply or reference this resource in production environments

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_s3_bucket" "insecure_public_bucket" {
  bucket = "forgeops-synthetic-insecure-test-bucket"
  acl    = "public-read"
}
