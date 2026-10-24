provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "k8s-auto-recovery-lab"
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }
}