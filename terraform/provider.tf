terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.48.0"
    }
  }
  #A backend defines where Terraform stores its state data files
  #By default,Terraform uses a backend called local, which stores state as a local file on disk.
  backend "s3" {
    bucket = "remote-state-prathyu-bucket"
    key    = "expense-infra-dev-frontend"
    region = "us-east-1"
    dynamodb_table  = "s3-remote-state-locking"
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
}