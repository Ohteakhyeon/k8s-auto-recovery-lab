variable "aws_region" {
  description = "AWS region for the EKS lab"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k8s-auto-recovery-lab"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "auto-recovery-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_public_access_cidrs" {
  description = "Allowed public CIDR blocks for EKS API access"
  type        = list(string)
}