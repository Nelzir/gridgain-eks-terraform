# GridGain 9 on AWS EKS - Terraform Deployment

Multi-region GridGain 9 deployment on AWS EKS with SQL Server sync and Data Center Replication (DCR).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              us-east-1                                           │
│  ┌──────────────────┐     ┌───────────────────────────────────────────────────┐ │
│  │  SQL Server EC2  │     │                 EKS Cluster (East)                │ │
│  │  (Windows/t3)    │     │  ┌─────────────┐    ┌──────────────────────────┐  │ │
│  │  - testdb        │◀────│──│ sqlserver-  │    │      GridGain 9          │  │ │
│  │  - CDC enabled   │     │  │ sync (Pod)  │───▶│      (3 nodes)           │  │ │
│  │  Port: 1433      │     │  │ polls: 30s  │    │      Port: 10800         │  │ │
│  └──────────────────┘     │  └─────────────┘    └────────────┬─────────────┘  │ │
│                           │                                  │                 │ │
│                           │  ┌─────────────┐                 │                 │ │
│                           │  │ table-setup │ (Job - creates  │                 │ │
│                           │  │    (Job)    │  GG9 tables)    │                 │ │
│                           │  └─────────────┘                 │                 │ │
│                           └──────────────────────────────────│─────────────────┘ │
└──────────────────────────────────────────────────────────────│───────────────────┘
                                                               │ DCR (VPC Peering)
                                                               │ Bidirectional
┌──────────────────────────────────────────────────────────────│───────────────────┐
│                              us-west-2                       │                   │
│                           ┌──────────────────────────────────▼─────────────────┐ │
│                           │                 EKS Cluster (West)                 │ │
│                           │               ┌──────────────────────────┐         │ │
│                           │               │      GridGain 9          │         │ │
│                           │               │      (3 nodes)           │         │ │
│                           │               │      Port: 10800         │         │ │
│                           │               └──────────────────────────┘         │ │
│                           └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **SQL Server → GridGain (East)**: `sqlserver-sync` pod polls for changes via CDC
2. **GridGain East ↔ West**: DCR replicates data bidirectionally via VPC peering
3. **Result**: Changes in SQL Server appear in both GridGain clusters

### Infrastructure Components

| Component | East (us-east-1) | West (us-west-2) |
|-----------|------------------|------------------|
| EKS Cluster | gg9-eks | gg9-eks-west |
| GridGain Nodes | 3x m7gd.2xlarge | 3x m7gd.2xlarge |
| System Nodes | 1x m7g.medium | 1x m7g.medium |
| SQL Server | t3.xlarge (Windows) | — |
| Sync Pod | sqlserver-sync | — |

### Storage (NVMe-Only)

All GridGain data uses local NVMe for maximum performance:

| Path | Purpose |
|------|---------|
| `/data/partitions` | Data partitions |
| `/data/cmg` | Cluster Management Group |
| `/data/metastorage` | Metastore |
| `/data/partitions-log` | RAFT partition logs |

Durability is provided by RAFT replication across 3 nodes per cluster.

## Prerequisites

1. **Terraform** >= 1.5.0
2. **AWS CLI** configured with credentials
3. **kubectl** for cluster management
4. **GridGain License** stored in AWS Secrets Manager

## Quick Start

### 1. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Required variables:
- `gg9_license_secret_arn` - ARN of GridGain license in Secrets Manager
- `gg9_admin_password` - Password for GridGain admin user
- `sqlserver_password` - Password for SQL Server admin

### 2. Deploy

```bash
terraform init
terraform apply
```

This automatically:
- Creates both EKS clusters with VPC peering
- Deploys GridGain 9 to both clusters
- Creates SQL Server EC2 with database and tables (CDC enabled)
- Runs table setup job to create matching tables in GridGain
- Starts the sync pod (ready to sync, but no data yet)

### 3. Configure kubeconfig

```bash
aws eks update-kubeconfig --region us-east-1 --name gg9-eks --alias gg9-eks
aws eks update-kubeconfig --region us-west-2 --name gg9-eks-west --alias gg9-eks-west
```

### 4. Verify Deployment

```bash
# Check pods in both clusters
kubectl --context gg9-eks get pods -n gridgain
kubectl --context gg9-eks-west get pods -n gridgain

# Verify sync pod is running (no data synced yet - tables are empty)
kubectl --context gg9-eks logs -l app=sqlserver-sync -n gridgain
```

### 5. Setup DCR (Data Center Replication)

After both clusters are healthy, configure bidirectional replication:

```bash
./scripts/setup-dcr.sh
```

This script:
- Creates tables on West cluster (to match East)
- Configures East → West replication
- Configures West → East replication
- Uses internal pod IPs via VPC peering

### 6. Insert Sample Data

After DCR is configured, insert sample data into SQL Server:

```bash
./scripts/insert-sample-data.sh
```

The data flows:
1. Inserted into SQL Server
2. Synced to GridGain East (via sqlserver-sync pod)
3. Replicated to GridGain West (via DCR)

### 7. Verify End-to-End

```bash
# Check data in East cluster
kubectl --context gg9-eks exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql "SELECT * FROM Customers"

# Check data in West cluster (replicated via DCR)
kubectl --context gg9-eks-west exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql "SELECT * FROM Customers"
```

## Configuration Reference

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for primary cluster |
| `cluster_name` | `gg9-eks` | EKS cluster name prefix |
| `cluster_version` | `1.30` | Kubernetes version |
| `node_instance_type` | `m7gd.2xlarge` | Instance type for GridGain nodes |
| `node_desired_size` | `3` | Number of GridGain nodes per cluster |
| `gg9_namespace` | `gridgain` | Kubernetes namespace |
| `gg9_chart_version` | `1.1.4` | GridGain Helm chart version |
| `gg9_license_secret_arn` | (required) | ARN of license in Secrets Manager |
| `gg9_admin_password` | (required) | GridGain admin password |
| `sqlserver_username` | `admin` | SQL Server admin username |
| `sqlserver_password` | (required) | SQL Server admin password |
| `sync_database` | `testdb` | SQL Server database to sync |
| `sync_tables` | `Orders,Customers,Products` | Tables to sync |

### License Setup

Create the license secret in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name gridgain-license \
  --secret-string file://gridgain-license.json \
  --region us-east-1
```

Get the ARN:

```bash
aws secretsmanager describe-secret --secret-id gridgain-license --query 'ARN' --output text
```

## Connecting to GridGain

### Port Forward (Development)

```bash
# East cluster
kubectl --context gg9-eks port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain

# West cluster (use different local port)
kubectl --context gg9-eks-west port-forward svc/gg9-west-gridgain9-headless 10801:10800 -n gridgain
```

**JDBC URLs:**
- East: `jdbc:ignite:thin://localhost:10800`
- West: `jdbc:ignite:thin://localhost:10801`

### Load Balancer (External)

```bash
# Get LB hostnames
eval $(terraform output -raw gridgain_lb_east_command)
eval $(terraform output -raw gridgain_lb_west_command)
```

## SQL Server Access

### SSM Port Forward (Recommended)

```bash
aws ssm start-session \
  --target $(terraform output -raw sqlserver_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["1433"],"localPortNumber":["1433"]}'
```

Then connect with DataGrip/SSMS:
- **Host**: `localhost:1433`
- **User**: `admin` (or value of `sqlserver_username`)
- **Password**: value of `sqlserver_password`
- **Database**: `testdb`

### RDP Access

```bash
terraform output sqlserver_rdp_command
# Connect via RDP to the public IP
```

## Network Architecture

### VPC CIDRs

| Region | VPC CIDR | Public Subnets |
|--------|----------|----------------|
| us-east-1 | 10.0.0.0/16 | 10.0.101-103.0/24 |
| us-west-2 | 10.1.0.0/16 | 10.1.101-103.0/24 |

### VPC Peering

- Cross-region peering with automatic route configuration
- Security groups allow GridGain ports (10800, 3344) between VPCs
- DCR uses internal pod IPs (not public internet)

## Troubleshooting

### Sync Pod: "Login failed"

SQL Server authentication issue. The user_data script should configure this automatically, but if it fails:

```bash
aws ssm send-command \
  --instance-ids $(terraform output -raw sqlserver_instance_id) \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Restart-Service -Name MSSQLSERVER -Force"]'
```

### Sync Pod: "Table not found"

The table setup job may have failed. Check its logs:

```bash
kubectl --context gg9-eks logs job/gridgain-table-setup -n gridgain
```

Re-run manually if needed:

```bash
kubectl --context gg9-eks delete job gridgain-table-setup -n gridgain
terraform apply -target=kubernetes_job.gridgain_table_setup
```

### DCR: "Replication to self"

Both clusters have the same cluster name. The West cluster uses `gg9-west` Helm release to differentiate.

### Pods Pending: Disk Pressure

NVMe may have stale data. Terminate affected nodes:

```bash
kubectl --context gg9-eks delete nodes -l role=gridgain
```

### DCR Connection Errors

Check security group rules allow traffic between VPCs on ports 10800 and 3344.

## Cleanup

```bash
terraform destroy
```

## File Structure

```
├── main.tf                    # East EKS cluster, providers
├── eks-west.tf                # West EKS cluster
├── vpc-east.tf                # East VPC (10.0.0.0/16)
├── vpc-west.tf                # West VPC (10.1.0.0/16)
├── vpc-peering.tf             # VPC peering configuration
├── gg9-helm.tf                # GridGain Helm releases
├── gg9-values.yaml            # Helm values (East)
├── gg9-values-west.yaml       # Helm values (West)
├── sqlserver.tf               # SQL Server EC2 + database setup
├── sqlserver-sync.tf          # Sync pod + table setup job
├── gg-query-client.tf         # Query client deployment
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── scripts/
│   ├── setup-dcr.sh           # DCR configuration (manual)
│   ├── insert-sample-data.sh  # Insert test data (manual)
│   ├── setup-tables.sh        # Full table setup (reference)
│   └── sqlserver-sync/        # Go sync tool source
├── terraform.tfvars.example   # Example variables
└── README.md                  # This file
```

## Instance Types with Local NVMe

| Instance | vCPU | Memory | NVMe Storage |
|----------|------|--------|--------------|
| m7gd.xlarge | 4 | 16 GiB | 1x 118 GiB |
| m7gd.2xlarge | 8 | 32 GiB | 1x 237 GiB |
| m7gd.4xlarge | 16 | 64 GiB | 1x 474 GiB |

> Local NVMe is ephemeral. Durability is provided by RAFT replication.
