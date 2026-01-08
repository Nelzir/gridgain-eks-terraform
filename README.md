# GridGain 9 on AWS EKS - Terraform Deployment

Multi-region GridGain 9 deployment on AWS EKS with VPC peering and Data Center Replication (DCR).

> **Deployment Status**: See [STATUS.md](STATUS.md) for current deployment progress.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              us-east-1                                       │
│  ┌──────────────────┐     ┌─────────────────────────────────────────────┐   │
│  │  SQL Server EC2  │     │              EKS Cluster (East)             │   │
│  │  (Windows/t3)    │────▶│  ┌─────────────┐    ┌──────────────────┐   │   │
│  │  Port: 1433      │     │  │ sqlserver-  │───▶│  GridGain 9      │   │   │
│  └──────────────────┘     │  │ sync (Pod)  │    │  (3 nodes)       │   │   │
│                           │  │ polls: 30s  │    │  Port: 10800     │   │   │
│                           │  └─────────────┘    └────────┬─────────┘   │   │
│                           └──────────────────────────────│─────────────┘   │
│                                                          │                  │
└──────────────────────────────────────────────────────────│──────────────────┘
                                                           │ DCR (VPC Peering)
┌──────────────────────────────────────────────────────────│──────────────────┐
│                              us-west-2                   │                  │
│                           ┌──────────────────────────────▼─────────────┐   │
│                           │              EKS Cluster (West)             │   │
│                           │             ┌──────────────────┐           │   │
│                           │             │  GridGain 9      │           │   │
│                           │             │  (3 nodes)       │           │   │
│                           │             │  Port: 10800     │           │   │
│                           │             └──────────────────┘           │   │
│                           └────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Multi-Region Setup
- **us-east-1**: Primary EKS cluster + SQL Server EC2 + Sync Pod
- **us-west-2**: Secondary EKS cluster (replica via DCR)
- **VPC Peering**: Cross-region connectivity for DCR traffic

### Node Groups (per cluster)
- **System Nodes**: 1x `m7g.medium` for system workloads (CoreDNS, EBS CSI driver)
- **GridGain Nodes**: 3x `m7gd.2xlarge` with local NVMe storage (tainted for GridGain only)

### Storage Architecture (NVMe-Only)

All GridGain storage uses local NVMe for maximum performance:

| Path | Purpose |
|------|---------|
| `/data/partitions` | Data partitions |
| `/data/cmg` | Cluster Management Group |
| `/data/metastorage` | Metastore |
| `/data/partitions-log` | RAFT partition logs |

Durability is provided by RAFT replication across 3 nodes per cluster.

## Prerequisites

1. **Terraform** >= 1.5.0
2. **AWS CLI** configured with appropriate credentials
3. **kubectl** for cluster management
4. **GridGain License** stored in AWS Secrets Manager

## Configuration

### 1. Create terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values.

### 2. Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for primary cluster |
| `aws_profile` | `null` | AWS CLI profile (uses default if not set) |
| `cluster_name` | `gg9-eks` | EKS cluster name prefix |
| `cluster_version` | `1.30` | Kubernetes version |
| `node_instance_type` | `m7gd.2xlarge` | Instance type for GridGain nodes |
| `node_desired_size` | `3` | Number of GridGain nodes per cluster |
| `node_min_size` | `3` | Minimum GridGain nodes |
| `node_max_size` | `6` | Maximum GridGain nodes |
| `gg9_namespace` | `gridgain` | Kubernetes namespace |
| `gg9_chart_version` | `1.1.4` | GridGain Helm chart version |
| `gg9_license_secret_arn` | (required) | ARN of AWS Secrets Manager secret |

### 3. License Setup (AWS Secrets Manager)

Create the secret:

```bash
aws secretsmanager create-secret \
  --name gridgain-license \
  --secret-string file://gridgain-license.json \
  --region us-east-1
```

Get the ARN for terraform.tfvars:

```bash
aws secretsmanager describe-secret --secret-id gridgain-license --query 'ARN' --output text
```

Add the ARN to `terraform.tfvars`:
```hcl
gg9_license_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:gridgain-license-AbCdEf"
```

## Deployment

### 1. Deploy Infrastructure

Initialize Terraform:

```bash
terraform init
```

Review and deploy:

```bash
terraform plan
terraform apply
```

### 2. Setup SQL Server Database

After deploy, set up the SQL Server database with Change Tracking.

**Option A**: Via SSM port forward + DataGrip/SSMS:

```bash
aws ssm start-session \
  --target $(terraform output -raw sqlserver_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["1433"],"localPortNumber":["1433"]}'
```

Then run `scripts/setup-sqlserver.sql` in your SQL client.

**Option B**: Via script (if sqlcmd available):

```bash
./scripts/setup-sqlserver.sh
```

### 3. Setup Data Center Replication (DCR)

After both clusters are running:

```bash
./scripts/setup-dcr.sh
```

This script:
- Creates sync tables (Customers, Products, Orders) on West cluster
- Creates a test table (`people`) on both clusters
- Configures bidirectional DCR using internal pod IPs
- Uses all pod IPs for redundant seed connections
- Verifies replication with test data

### Verify Deployment

Check East cluster:

```bash
kubectl --context gg9-eks get pods -n gridgain
kubectl --context gg9-eks -n gridgain exec -it gg9-gridgain9-0 -- \
  /opt/gridgain9cli/bin/gridgain9 cluster status
```

Check West cluster:

```bash
kubectl --context gg9-eks-west get pods -n gridgain
kubectl --context gg9-eks-west -n gridgain exec -it gg9-west-gridgain9-0 -- \
  /opt/gridgain9cli/bin/gridgain9 cluster status
```

Check DCR status:

```bash
kubectl --context gg9-eks -n gridgain exec -it gg9-gridgain9-0 -- \
  /opt/gridgain9cli/bin/gridgain9 dcr list
```

## Connecting to GridGain

### Port Forward (Recommended for Development)

East cluster:

```bash
kubectl --context gg9-eks port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain
```

West cluster:

```bash
kubectl --context gg9-eks-west port-forward svc/gg9-west-gridgain9-headless 10801:10800 -n gridgain
```

**JDBC Connection:**

| Cluster | URL |
|---------|-----|
| East | `jdbc:ignite:thin://localhost:10800` |
| West | `jdbc:ignite:thin://localhost:10801` |

### Load Balancer (External Access)

Get Load Balancer hostnames via Terraform outputs:

```bash
eval $(terraform output -raw gridgain_lb_east_command)
eval $(terraform output -raw gridgain_lb_west_command)
```

## Network Architecture

### VPC CIDRs
- **East (us-east-1)**: 10.0.0.0/16
  - Public subnets: 10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24
- **West (us-west-2)**: 10.1.0.0/16
  - Public subnets: 10.1.101.0/24, 10.1.102.0/24, 10.1.103.0/24

### VPC Peering
- Cross-region peering with automatic route table configuration
- Security group rules allow GridGain ports (10800, 3344) between VPCs
- DCR traffic flows internally via pod IPs, not through public internet

### No NAT Gateway
Public subnets with auto-assign public IPs (cost optimization for PoC).

## SQL Server

A Windows EC2 instance with SQL Server 2022 Standard edition using the AWS-provided licensed AMI.

| Setting | Value |
|---------|-------|
| **Edition** | Standard (AWS licensed AMI) |
| **Instance** | t3.xlarge (4 vCPU, 16GB RAM) |
| **Storage** | 100GB gp3 |
| **Port** | 1433 |
| **License Cost** | ~$0.05/hr (~$36/month) |
| **Credentials** | `admin` / `sqlserver_password` from terraform.tfvars |

The instance is ready to use immediately after deploy (~2-3 min boot time).

### Connect from DataGrip (Port Forward)

Use SSM port forwarding to connect securely without opening the security group.

Install SSM plugin (one-time):

```bash
brew install --cask session-manager-plugin
```

Start port forward (keep terminal open):

```bash
aws ssm start-session \
  --target $(terraform output -raw sqlserver_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["1433"],"localPortNumber":["1433"]}'
```

Then in DataGrip:
- **Host**: `localhost`
- **Port**: `1433`
- **Authentication**: SQL Server
- **User**: `sqlserver_username` from terraform.tfvars (or Windows Auth)
- **Password**: `sqlserver_password` from terraform.tfvars
- **Database**: `testdb`

## SQL Server Sync

The sync tool polls SQL Server using Change Tracking and pushes changes to GridGain.

### Build and Push Docker Image

Build for ARM (Graviton nodes):

```bash
cd scripts/sqlserver-sync
docker buildx build --platform linux/arm64 -t nelzir/sqlserver-sync:latest --push .
```

Or build for AMD64:

```bash
docker buildx build --platform linux/amd64 -t nelzir/sqlserver-sync:latest --push .
```

### Configuration

The sync is configured via Terraform variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `sync_image` | `nelzir/sqlserver-sync:latest` | Docker image |
| `sync_database` | `testdb` | SQL Server database |
| `sync_tables` | `Orders,Customers,Products` | Tables to sync |

### Polling Interval

Default is `30s`. Accepts Go duration format: `30s`, `1m`, `500ms`, etc.

Configure in [sqlserver-sync.tf](sqlserver-sync.tf) or the ConfigMap.

## Cleanup

Destroy all resources in both regions:

```bash
terraform destroy
```

## File Structure

```
├── main.tf                    # East EKS cluster, providers, addons
├── eks-west.tf                # West EKS cluster and addons
├── vpc-east.tf                # East VPC (10.0.0.0/16)
├── vpc-west.tf                # West VPC (10.1.0.0/16)
├── vpc-peering.tf             # VPC peering and security group rules
├── gg9-helm.tf                # GridGain Helm releases (both clusters)
├── gg9-values.yaml            # Helm values for East cluster
├── gg9-values-west.yaml       # Helm values for West cluster
├── sqlserver.tf               # SQL Server EC2 instance
├── sqlserver-sync.tf          # Sync pod deployment (ConfigMap, Secret, Deployment)
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── scripts/
│   ├── setup-dcr.sh           # DCR setup script
│   ├── setup-sqlserver.sh     # SQL Server database setup
│   ├── setup-sqlserver.sql    # SQL script for manual execution
│   └── sqlserver-sync/        # Go sync tool
│       ├── main.go            # Sync logic with Change Tracking
│       ├── gridgain.go        # GridGain REST client
│       ├── Dockerfile         # Container build
│       └── k8s/               # K8s manifests (reference)
├── terraform.tfvars.example   # Example variables file
├── CHANGELOG.md               # Change history
├── STATUS.md                  # Current deployment status
└── README.md                  # This file
```

## Troubleshooting

### Pods Pending - Disk Pressure

If nodes show disk pressure taint, the NVMe may have stale data. Terminate the affected EC2 instances to get fresh nodes:

```bash
kubectl --context gg9-eks-west delete nodes -l role=gridgain
```

### DCR "Replication to self"

Both clusters have the same name. The west cluster must use a different Helm release name (`gg9-west` vs `gg9`).

### Pods Can't Reach Other Cluster

Check security group rules allow traffic from the peer VPC CIDR on ports 10800 and 3344.

### DCR Connection Errors

Use pod IPs instead of LoadBalancer addresses for internal VPC peering traffic. The `setup-dcr.sh` script handles this automatically.

## Instance Types with Local NVMe

| Instance | vCPU | Memory | NVMe Storage |
|----------|------|--------|--------------|
| `m7gd.xlarge` | 4 | 16 GiB | 1x 118 GiB |
| `m7gd.2xlarge` | 8 | 32 GiB | 1x 237 GiB |
| `m7gd.4xlarge` | 16 | 64 GiB | 1x 474 GiB |

> **Note**: Local NVMe is ephemeral - data is lost if the node is terminated. Durability is provided by RAFT replication across nodes.
