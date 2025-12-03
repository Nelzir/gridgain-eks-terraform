# -----------------------
# EKS Cluster Outputs
# -----------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA cert data"
  value       = module.eks.cluster_certificate_authority_data
}

output "kubeconfig_command" {
  description = "Command to update your kubeconfig after apply"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "node_group_info" {
  description = "Node group sizing info"
  value = {
    instance_type = var.node_instance_type
    desired_size  = var.node_desired_size
    min_size      = var.node_min_size
    max_size      = var.node_max_size
  }
}