# -----------------------
# AWS + EKS Variables
# -----------------------

variable "aws_region" {
  description = "AWS region to deploy EKS into"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (leave empty to use default credentials)"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gg9-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.30"
}

# -----------------------
# Node Group Config
# -----------------------

variable "node_instance_type" {
  description = "Instance type for GG9 nodes"
  type        = string
  default     = "m7gd.2xlarge"
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 6
}

# -----------------------
# GG9 Helm Chart Inputs
# -----------------------

variable "gg9_namespace" {
  description = "Namespace to deploy GridGain 9"
  type        = string
  default     = "gridgain"
}

variable "gg9_chart_version" {
  description = "Version of the GG9 Helm chart"
  type        = string
  default     = "1.1.4" # You can update once we wire helm_release
}

variable "gg9_values_file" {
  description = "Path to the GG9 Helm values.yaml"
  type        = string
  default     = "./gg9-values.yaml"
}

variable "gg9_license_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the GridGain license"
  type        = string
}

# -----------------------
# SQL Server POC
# -----------------------

variable "sqlserver_username" {
  description = "Username for SQL Server admin account"
  type        = string
  default     = "admin"
}

variable "sqlserver_password" {
  description = "Password for SQL Server admin account (must meet strong password requirements)"
  type        = string
  sensitive   = true
}

# -----------------------
# GridGain Authentication
# -----------------------

variable "gg9_admin_username" {
  description = "Username for GridGain admin user"
  type        = string
  default     = "admin"
}

variable "gg9_admin_password" {
  description = "Password for GridGain admin user"
  type        = string
  sensitive   = true
}

# -----------------------
# SQL Server Sync
# -----------------------

variable "sync_image" {
  description = "Docker image for sqlserver-sync"
  type        = string
  default     = "nelzir/sqlserver-sync:latest"
}

variable "sync_database" {
  description = "SQL Server database to sync"
  type        = string
  default     = "testdb"
}

variable "sync_tables" {
  description = "Comma-separated list of tables to sync"
  type        = string
  default     = "Orders,Customers,Products"
}