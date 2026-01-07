# =========================
# US-West-2 EKS Cluster (Secondary / DR)
# =========================

# -----------------------
# Kubernetes provider for west cluster (exec-based auth for fresh tokens)
# -----------------------
provider "kubernetes" {
  alias = "west"

  host                   = module.eks_west.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_west.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = var.aws_profile != null ? ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", "us-west-2", "--profile", var.aws_profile] : ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", "us-west-2"]
  }
}

provider "helm" {
  alias = "west"

  kubernetes {
    host                   = module.eks_west.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_west.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = var.aws_profile != null ? ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", "us-west-2", "--profile", var.aws_profile] : ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", "us-west-2"]
    }
  }
}

# -----------------------
# EKS Cluster
# -----------------------
module "eks_west" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  providers = {
    aws = aws.west
  }

  cluster_name    = "${var.cluster_name}-west"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc_west.vpc_id
  subnet_ids = module.vpc_west.public_subnets

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  create_kms_key              = false
  cluster_encryption_config   = {}
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []

  eks_managed_node_groups = {
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

    gg9 = {
      node_group_name = "gg9-gridgain"

      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_ARM_64_STANDARD"

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      capacity_type = "ON_DEMAND"

      labels = {
        role = "gridgain"
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "gridgain"
          effect = "NO_SCHEDULE"
        }
      }

      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        set -ex

        NVME_DEVICE=$(lsblk -o NAME,MODEL -d | grep "Instance Storage" | awk '{print "/dev/"$1}' | head -1)

        if [ -n "$NVME_DEVICE" ]; then
          if ! blkid "$NVME_DEVICE"; then
            mkfs.xfs -f "$NVME_DEVICE"
          fi

          mkdir -p /mnt/nvme
          mount "$NVME_DEVICE" /mnt/nvme

          echo "$NVME_DEVICE /mnt/nvme xfs defaults,nofail 0 2" >> /etc/fstab

          chown 1001:1001 /mnt/nvme
          chmod 755 /mnt/nvme
        fi
      EOT
    }
  }
}

# -----------------------
# Auto-configure kubectl context for west cluster
# -----------------------
resource "null_resource" "update_kubeconfig_west" {
  triggers = {
    cluster_name = module.eks_west.cluster_name
  }

  provisioner "local-exec" {
    command = var.aws_profile != null ? "aws eks update-kubeconfig --name ${module.eks_west.cluster_name} --region us-west-2 --profile ${var.aws_profile} --alias ${module.eks_west.cluster_name}" : "aws eks update-kubeconfig --name ${module.eks_west.cluster_name} --region us-west-2 --alias ${module.eks_west.cluster_name}"
  }

  depends_on = [module.eks_west]
}

# -----------------------
# IRSA for EBS CSI Driver (West)
# -----------------------
module "ebs_csi_irsa_west" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  providers = {
    aws = aws.west
  }

  role_name             = "${var.cluster_name}-west-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_west.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# -----------------------
# GP3 StorageClass (West)
# -----------------------
resource "kubernetes_storage_class" "gp3_west" {
  provider = kubernetes.west

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

  depends_on = [aws_eks_addon.ebs_csi_west]
}

# -----------------------
# EKS Addons (West)
# -----------------------
resource "aws_eks_addon" "coredns_west" {
  provider                    = aws.west
  cluster_name                = module.eks_west.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks_west]
}

resource "aws_eks_addon" "ebs_csi_west" {
  provider                    = aws.west
  cluster_name                = module.eks_west.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.37.0-eksbuild.1"
  service_account_role_arn    = module.ebs_csi_irsa_west.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    module.eks_west,
    module.ebs_csi_irsa_west
  ]
}
