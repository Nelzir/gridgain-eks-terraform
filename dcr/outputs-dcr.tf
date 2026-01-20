# -----------------------
# US-East-1 EKS Cluster Outputs (Primary)
# -----------------------

output "cluster_name_east" {
  description = "EKS cluster name (us-east-1)"
  value       = module.eks.cluster_name
}

output "cluster_endpoint_east" {
  description = "API server endpoint (us-east-1)"
  value       = module.eks.cluster_endpoint
}

output "vpc_id_east" {
  description = "VPC ID (us-east-1)"
  value       = module.vpc_east.vpc_id
}

output "kubeconfig_command_east" {
  description = "Command to update kubeconfig for east cluster"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}

# -----------------------
# US-West-2 EKS Cluster Outputs (Secondary)
# -----------------------

output "cluster_name_west" {
  description = "EKS cluster name (us-west-2)"
  value       = module.eks_west.cluster_name
}

output "cluster_endpoint_west" {
  description = "API server endpoint (us-west-2)"
  value       = module.eks_west.cluster_endpoint
}

output "vpc_id_west" {
  description = "VPC ID (us-west-2)"
  value       = module.vpc_west.vpc_id
}

output "kubeconfig_command_west" {
  description = "Command to update kubeconfig for west cluster"
  value       = "aws eks update-kubeconfig --region us-west-2 --name ${module.eks_west.cluster_name}"
}

# -----------------------
# VPC Peering Output
# -----------------------

output "vpc_peering_connection_id" {
  description = "VPC peering connection ID between east and west"
  value       = aws_vpc_peering_connection.east_west.id
}
