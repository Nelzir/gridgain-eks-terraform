# GridGain 9 on AWS EKS - Terraform Deployment

This Terraform configuration deploys a GridGain 9 cluster on AWS EKS with dedicated node groups.

## Architecture

- **Default Node Group**: 2x `m7g.medium` instances for system workloads (CoreDNS, EBS CSI driver, etc.)
- **GridGain Node Group**: 3x `m7gd.2xlarge` instances dedicated to GridGain pods (tainted)

## Prerequisites

1. **Terraform** >= 1.5.0
2. **AWS CLI** configured with appropriate credentials
3. **kubectl** for cluster management
4. **Helm** (optional, for manual operations)
5. **GridGain License** file (JSON format)

## Configuration

### 1. AWS Profile

Update the AWS profile in `main.tf`:

```hcl
provider "aws" {
  region  = var.aws_region
  profile = "your-profile-name"  # Change this
}
```

Also update the kubeconfig command:

```hcl
resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region} --profile your-profile-name"
  }
}
```

### 2. Variables (variables.tf)

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `cluster_name` | `gg9-eks` | EKS cluster name |
| `cluster_version` | `1.30` | Kubernetes version |
| `node_instance_type` | `m7gd.2xlarge` | Instance type for GridGain nodes |
| `node_desired_size` | `3` | Number of GridGain nodes |
| `node_min_size` | `3` | Minimum GridGain nodes |
| `node_max_size` | `6` | Maximum GridGain nodes |
| `gg9_namespace` | `gridgain` | Kubernetes namespace |
| `gg9_chart_version` | `1.1.1` | GridGain Helm chart version |
| `gg9_license_file` | `../gridgain-license.json` | Path to license file |

### 3. License File

Place your GridGain license file at the path specified by `gg9_license_file`. The default expects:

```
gridgain/
├── gridgain-license.json    # Your license file here
└── q2/
    └── terraform/
        └── (terraform files)
```

### 4. GridGain Configuration (gg9-values.yaml)

Key sections to customize:

#### Node Resources
```yaml
resources:
  requests:
    cpu: "4"
    memory: "24Gi"
  limits:
    cpu: "7"
    memory: "28Gi"
```

#### Persistence (Hybrid Storage)
```yaml
# EBS for metadata
persistence:
  volumes:
    persistence:
      enabled: true
      mountPath: /persistence
      storageClassName: gp3
      size: 100Gi

# Local NVMe for data
extraVolumes:
  - name: nvme-data
    hostPath:
      path: /mnt/nvme

extraVolumeMounts:
  - name: nvme-data
    mountPath: /data

gridgainWorkDir: /data
```

#### Node Finder (must match your Helm release name)
```yaml
nodeFinder {
  type = STATIC
  netClusterNodes = [
    "gg9-gridgain9-headless:3344"  # Format: <release-name>-gridgain9-headless:3344
  ]
}
```

## Deployment

### Initial Setup

```bash
# Configure AWS profile
aws configure --profile your-profile-name

# Initialize Terraform
terraform init

# Review changes
terraform plan

# Deploy
terraform apply
```

### Verify Deployment

```bash
# Check nodes
kubectl get nodes

# Check GridGain pods
kubectl get pods -n gridgain

# Check cluster status
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 cluster status

# Check cluster topology
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 cluster topology physical --url=http://localhost:10300
```

## Connecting to GridGain

### Port Forward for JDBC Access

```bash
# Start port forwarding (run in background or separate terminal)
kubectl port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain

# For REST API access
kubectl port-forward svc/gg9-gridgain9-headless 10300:10300 -n gridgain
```

### JDBC Connection String

With port-forward running:
```
jdbc:ignite:thin://localhost:10800
```

### Example: Connect with DBeaver/DataGrip

1. Start port-forward: `kubectl port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain`
2. Add new connection in your SQL client
3. Use driver: Apache Ignite (or GridGain)
4. Host: `localhost`
5. Port: `10800`

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

## Troubleshooting

### Pods Pending - Insufficient Memory

Reduce memory requests in `gg9-values.yaml` or use larger instance types.

### Init Job Failing - License Not Found

Ensure license file path is correct and file contains valid JSON license.

### Nodes Not Discovering Each Other

Check `nodeFinder.netClusterNodes` matches your Helm release name:
- Release name `gg9` → `gg9-gridgain9-headless:3344`
- Release name `my-release` → `my-release-gridgain9-headless:3344`

### CoreDNS/EBS CSI Pending

Ensure the default node group exists and has available capacity.

## File Structure

```
terraform/
├── main.tf           # EKS cluster, node groups, addons
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── gg9-helm.tf       # GridGain Helm release
├── gg9-values.yaml   # GridGain Helm values
└── README.md         # This file
```

## Storage Architecture

This setup uses a hybrid storage approach for optimal performance:

- **Local NVMe** (`/data`): High-performance storage for GridGain data (partitions, indexes)
- **EBS gp3** (`/persistence`): Durable storage for metadata (RAFT logs, metastore)

### Why This Approach?

| Storage | Use Case | Benefits |
|---------|----------|----------|
| Local NVMe | Data partitions, indexes | Ultra-low latency, high IOPS |
| EBS gp3 | RAFT logs, metastore | Durability, survives node replacement |

### Instance Types with Local NVMe

Use `m7gd.*` or `r7gd.*` instances which include local NVMe:

| Instance | vCPU | Memory | NVMe Storage |
|----------|------|--------|--------------|
| `m7gd.xlarge` | 4 | 16 GiB | 1x 118 GiB |
| `m7gd.2xlarge` | 8 | 32 GiB | 1x 237 GiB |
| `m7gd.4xlarge` | 16 | 64 GiB | 1x 474 GiB |

> **Important**: Local NVMe data is ephemeral - it's lost if the node is terminated. RAFT replication provides data durability across nodes.
