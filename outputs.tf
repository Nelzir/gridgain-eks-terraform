# -----------------------
# US-East-1 EKS Cluster Outputs
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
# US-West-2 EKS Cluster Outputs
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

# -----------------------
# Node Group Info
# -----------------------

output "node_group_info" {
  description = "Node group sizing info (same for both clusters)"
  value = {
    instance_type = var.node_instance_type
    desired_size  = var.node_desired_size
    min_size      = var.node_min_size
    max_size      = var.node_max_size
  }
}

# -----------------------
# SQL Server POC Outputs
# -----------------------

output "sqlserver_private_ip" {
  description = "SQL Server private IP (for EKS connectivity)"
  value       = aws_instance.sqlserver.private_ip
}

output "sqlserver_public_ip" {
  description = "SQL Server public IP (for RDP access)"
  value       = aws_instance.sqlserver.public_ip
}

output "sqlserver_connection_string" {
  description = "SQL Server connection string for sync tool"
  value       = "sqlserver://${var.sqlserver_username}:${var.sqlserver_password}@${aws_instance.sqlserver.private_ip}:1433?database=testdb"
  sensitive   = true
}

output "sqlserver_rdp_command" {
  description = "RDP connection info"
  value       = "Connect via RDP to ${aws_instance.sqlserver.public_ip}:3389"
}

output "sqlserver_instance_id" {
  description = "SQL Server EC2 instance ID (for creating AMI)"
  value       = aws_instance.sqlserver.id
}

output "sqlserver_password" {
  description = "SQL Server sa/admin password"
  value       = var.sqlserver_password
  sensitive   = true
}

output "sqlserver_create_ami_command" {
  description = "Command to create AMI after SQL Server install completes (~15 min)"
  value       = "aws ec2 create-image --instance-id ${aws_instance.sqlserver.id} --name 'sqlserver-2022-developer-${formatdate("YYYY-MM-DD", timestamp())}' --description 'SQL Server 2022 Developer with CDC' --no-reboot"
}

# -----------------------
# GridGain Load Balancer Commands
# -----------------------

output "gridgain_lb_east_command" {
  description = "Command to get GridGain East cluster Load Balancer hostname"
  value       = "kubectl --context ${var.cluster_name} get svc gg9-gridgain9-client -n ${var.gg9_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "gridgain_lb_west_command" {
  description = "Command to get GridGain West cluster Load Balancer hostname"
  value       = "kubectl --context ${var.cluster_name}-west get svc gg9-west-gridgain9-client -n ${var.gg9_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
