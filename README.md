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

### 1. Create terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `aws_profile` | `null` | AWS CLI profile (uses default if not set) |
| `cluster_name` | `gg9-eks` | EKS cluster name |
| `cluster_version` | `1.30` | Kubernetes version |
| `node_instance_type` | `m7gd.2xlarge` | Instance type for GridGain nodes |
| `node_desired_size` | `3` | Number of GridGain nodes |
| `node_min_size` | `3` | Minimum GridGain nodes |
| `node_max_size` | `6` | Maximum GridGain nodes |
| `gg9_namespace` | `gridgain` | Kubernetes namespace |
| `gg9_chart_version` | `1.1.1` | GridGain Helm chart version |
| `gg9_license_secret_arn` | (required) | ARN of AWS Secrets Manager secret containing the GridGain license |

### 3. License Setup (AWS Secrets Manager)

Store your GridGain license in AWS Secrets Manager:

```bash
# Create the secret (replace with your actual license content)
aws secretsmanager create-secret \
  --name gridgain-license \
  --secret-string file://gridgain-license.json \
  --region us-east-1

# Get the ARN for terraform.tfvars
aws secretsmanager describe-secret --secret-id gridgain-license --query 'ARN' --output text
```

Then add the ARN to your `terraform.tfvars`:
```hcl
gg9_license_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:gridgain-license-AbCdEf"
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

#### Storage (Local NVMe)
```yaml
# Local NVMe for all data (maximum performance)
extraVolumes:
  - name: nvme-data
    hostPath:
      path: /mnt/nvme

extraVolumeMounts:
  - name: nvme-data
    mountPath: /data

gridgainWorkDir: /data
```

Durability is provided by RAFT replication across 3 nodes.

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

### Option 1: Load Balancer

The deployment provisions an AWS Classic Load Balancer for external client access:

```bash
# Get the Load Balancer hostname
kubectl get svc gg9-gridgain9-client -n gridgain -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**JDBC Connection String:**
```
jdbc:ignite:thin://<LB_HOSTNAME>:10800
```

> **Note**: The Load Balancer may take 2-3 minutes to provision and become healthy after deployment.

The client service uses `externalTrafficPolicy: Local` to avoid extra network hops and preserve client source IPs.

### Option 2: Port Forward (Development)

```bash
# Start port forwarding (run in background or separate terminal)
kubectl port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain

# For REST API access
kubectl port-forward svc/gg9-gridgain9-headless 10300:10300 -n gridgain
```

**JDBC Connection String:**
```
jdbc:ignite:thin://localhost:10800
```

### Example: Connect with DBeaver/DataGrip

**Using Load Balancer:**
1. Get LB hostname: `kubectl get svc gg9-gridgain9-client -n gridgain`
2. Add new connection in your SQL client
3. Use driver: Apache Ignite (or GridGain)
4. Host: `<LB_HOSTNAME>`
5. Port: `10800`

**Using Port Forward:**
1. Start port-forward: `kubectl port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain`
2. Host: `localhost`
3. Port: `10800`

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

## Multi-Region & Data Center Replication (DCR)

For multi-region deployments with cross-cluster replication, see the [DCR Guide](dcr/README.md).

**Highlights:**
- VPC Peering vs Transit Gateway connectivity options
- Using the client LoadBalancer service for stable DCR endpoints
- Bidirectional replication configuration
- Security group and routing setup

## File Structure

```
├── main.tf                    # EKS cluster, node groups, addons
├── vpc.tf                     # VPC configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── gg9-helm.tf                # GridGain Helm release + license secret
├── gg9-values.yaml            # GridGain Helm values
├── terraform.tfvars.example   # Example variables file
└── dcr/                       # Multi-region DCR setup (see dcr/README.md)
```

## Instance Types with Local NVMe

Use `m7gd.*` or `r7gd.*` instances which include local NVMe:

| Instance | vCPU | Memory | NVMe Storage |
|----------|------|--------|--------------|
| `m7gd.xlarge` | 4 | 16 GiB | 1x 118 GiB |
| `m7gd.2xlarge` | 8 | 32 GiB | 1x 237 GiB |
| `m7gd.4xlarge` | 16 | 64 GiB | 1x 474 GiB |

> **Note**: Local NVMe is ephemeral. Durability is provided by RAFT replication across 3 nodes.
