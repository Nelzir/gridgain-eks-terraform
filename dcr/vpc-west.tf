# =========================
# US-West-2 VPC (Secondary / DR)
# =========================

provider "aws" {
  alias   = "west"
  region  = "us-west-2"
  profile = var.aws_profile
}

module "vpc_west" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  providers = {
    aws = aws.west
  }

  name = "${var.cluster_name}-west"
  cidr = "10.1.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]

  enable_nat_gateway           = false
  single_nat_gateway           = false
  enable_dns_hostnames         = true
  enable_dns_support           = true
  map_public_ip_on_launch      = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb"                          = 1
    "kubernetes.io/cluster/${var.cluster_name}-west" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                 = 1
    "kubernetes.io/cluster/${var.cluster_name}-west" = "shared"
  }

  tags = {
    Environment = "poc"
    Region      = "us-west-2"
  }
}
