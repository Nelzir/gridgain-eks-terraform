terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# -----------------------
# AWS provider
# -----------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# -----------------------
# VPC references (defined in vpc-east.tf)
# -----------------------

# -----------------------
# EKS cluster (via terraform-aws-modules/eks)
# -----------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc_east.vpc_id
  subnet_ids = module.vpc_east.public_subnets

  # Public API endpoint for PoC (lock down with CIDRs later)
  cluster_endpoint_public_access = true

  # Give the IAM principal running Terraform full cluster-admin RBAC
  enable_cluster_creator_admin_permissions = true

  # Disable KMS and logging to prevent orphaned resources on failed destroys
  create_kms_key              = false
  cluster_encryption_config   = {}
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []

  # ============================
  # Managed Node Groups
  # ============================
  eks_managed_node_groups = {
    # Default node group for system workloads (CoreDNS, EBS CSI, etc.)
    default = {
      node_group_name = "default-system"

      instance_types = ["m7g.medium"]
      ami_type       = "AL2023_ARM_64_STANDARD"

      desired_size = 1
      min_size     = 1
      max_size     = 2

      capacity_type = "ON_DEMAND"

      labels = {
        role = "system"
      }
    }

    # Dedicated node group for GridGain
    gg9 = {
      node_group_name = "gg9-gridgain"

      # m7gd.* = Graviton (ARM) with local NVMe
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_ARM_64_STANDARD"

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      capacity_type = "ON_DEMAND"

      # Must match Helm nodeSelector:
      labels = {
        role = "gridgain"
      }

      # Must match Helm tolerations:
      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "gridgain"
          effect = "NO_SCHEDULE"
        }
      }

      # Bootstrap script to format and mount NVMe drive
      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        set -ex

        # Find NVMe instance store device (not EBS volumes)
        NVME_DEVICE=$(lsblk -o NAME,MODEL -d | grep "Instance Storage" | awk '{print "/dev/"$1}' | head -1)

        if [ -n "$NVME_DEVICE" ]; then
          # Create filesystem if not exists
          if ! blkid "$NVME_DEVICE"; then
            mkfs.xfs -f "$NVME_DEVICE"
          fi

          # Create mount point and mount
          mkdir -p /mnt/nvme
          mount "$NVME_DEVICE" /mnt/nvme

          # Add to fstab for persistence across reboots
          echo "$NVME_DEVICE /mnt/nvme xfs defaults,nofail 0 2" >> /etc/fstab

          # Set permissions for GridGain (uid 1001)
          chown 1001:1001 /mnt/nvme
          chmod 755 /mnt/nvme
        fi
      EOT
    }
  }
}

# -----------------------
# Cluster authentication for Kubernetes & Helm providers
# -----------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# -----------------------
# Auto-configure kubectl context
# -----------------------
resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name = module.eks.cluster_name
  }

  provisioner "local-exec" {
    command = var.aws_profile != null ? "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile}" : "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
  }

  depends_on = [module.eks]
}

# -----------------------
# Kubernetes provider (exec-based auth for fresh tokens)
# -----------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = var.aws_profile != null ? ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile] : ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# -----------------------
# Helm provider (exec-based auth for fresh tokens)
# -----------------------
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = var.aws_profile != null ? ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile] : ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# -----------------------
# IRSA for EBS CSI Driver
# -----------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# -----------------------
# GP3 StorageClass (recommended over gp2)
# -----------------------
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# -----------------------
# EBS CSI Driver Addon (separate resource for proper dependency order)
# -----------------------
# -----------------------
# CoreDNS Addon
# -----------------------
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.37.0-eksbuild.1"
  service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    module.eks,
    module.ebs_csi_irsa
  ]
}