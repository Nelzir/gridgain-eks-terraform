# GridGain Data Center Replication (DCR)

This guide covers configuring GridGain 9 Data Center Replication between two EKS clusters in different AWS regions.

## Overview

DCR enables bidirectional data replication between GridGain clusters, providing:
- **Disaster Recovery**: Automatic failover to secondary region
- **Geographic Distribution**: Low-latency access from multiple regions
- **Data Consistency**: Near real-time synchronization

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              us-east-1 (VPC: 10.0.0.0/16)                   │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  EKS Cluster (East)                                                    │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │  GridGain 9 (3 nodes)                                           │   │ │
│  │  │  Headless: gg9-gridgain9-headless:3344 (discovery)              │   │ │
│  │  │  Client:   gg9-gridgain9-client:10800  (external access)        │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                         ┌────────────┴────────────┐
                         │   VPC Peering    OR     │
                         │   Transit Gateway       │
                         └────────────┬────────────┘
                                      │
┌─────────────────────────────────────│───────────────────────────────────────┐
│                              us-west-2 (VPC: 10.1.0.0/16)                   │
│  ┌──────────────────────────────────│─────────────────────────────────────┐ │
│  │  EKS Cluster (West)              │                                     │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │  GridGain 9 (3 nodes)                                           │   │ │
│  │  │  Headless: gg9-west-gridgain9-headless:3344 (discovery)         │   │ │
│  │  │  Client:   gg9-west-gridgain9-client:10800  (external access)   │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. Two EKS clusters deployed (see main README for single cluster setup)
2. Non-overlapping VPC CIDRs (e.g., 10.0.0.0/16 and 10.1.0.0/16)
3. Network connectivity between clusters on port 10800

## Network Connectivity

Choose based on your requirements:

| Option | Best For | Cost |
|--------|----------|------|
| **VPC Peering** | Simple 2-region setups | Free (data transfer only) |
| **Transit Gateway** | Enterprise, multi-VPC, on-prem | ~$0.05/hr per attachment |

### VPC Peering Setup

See [vpc-peering.tf](vpc-peering.tf) for the Terraform configuration.

Key components:
1. Create peering connection from East → West
2. Accept peering in West region
3. Add routes to both VPC route tables
4. Update security groups for port 10800

### Transit Gateway Setup

For Transit Gateway, you'll need:
1. Transit Gateway in each region
2. TGW peering between regions
3. VPC attachments
4. Route table configuration

## DCR Endpoint Options

The Helm chart creates two services:
- **Headless Service**: For internal cluster discovery
- **Client Service**: LoadBalancer for external access (including DCR)

### Option 1: Pod IPs (Direct)

Use direct pod IPs for DCR. Lower latency but IPs change on pod restart.

```bash
./setup-dcr.sh
```

### Option 2: Client Service (LoadBalancer)

Use the client service endpoint. Stable endpoint that survives pod restarts.

```bash
./setup-dcr-tgw.sh
```

## Security Groups

Allow DCR traffic between VPCs on port 10800:

```hcl
resource "aws_security_group_rule" "east_allow_west_dcr" {
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = ["10.1.0.0/16"]  # West VPC CIDR
  security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "west_allow_east_dcr" {
  provider          = aws.west
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # East VPC CIDR
  security_group_id = module.eks_west.node_security_group_id
}
```

## Configuring DCR

### Step 1: Create Tables on Both Clusters

Tables must exist on both clusters before enabling DCR:

```sql
-- Run on BOTH clusters
CREATE TABLE Customers (Id INT PRIMARY KEY, Name VARCHAR, Email VARCHAR);
CREATE TABLE Products (Id INT PRIMARY KEY, Name VARCHAR, Price DECIMAL);
```

### Step 2: Configure DCR Channels

DCR is configured on the **receiver** cluster, pointing to the **source** cluster.

**East → West (run on West cluster):**

```bash
kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr create \
    --name east-to-west \
    --source-cluster-address <EAST_ENDPOINT>:10800 \
    --username admin --password <password>

kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr start \
    --name east-to-west --schema=PUBLIC --all
```

**West → East (run on East cluster):**

```bash
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr create \
    --name west-to-east \
    --source-cluster-address <WEST_ENDPOINT>:10800 \
    --username admin --password <password>

kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr start \
    --name west-to-east --schema=PUBLIC --all
```

### Step 3: Verify Replication

```bash
# Insert on East
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql \
  "INSERT INTO Customers VALUES (1, 'John', 'john@example.com')"

# Verify on West
kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql "SELECT * FROM Customers"
```

## DCR Commands

```bash
gridgain9 dcr list                          # List channels
gridgain9 dcr status --name east-to-west    # Check status
gridgain9 dcr stop --name east-to-west --all    # Stop replication
gridgain9 dcr delete --name east-to-west    # Delete channel
```

## Files

| File | Description |
|------|-------------|
| `vpc-east.tf` | East region VPC (10.0.0.0/16) |
| `vpc-west.tf` | West region VPC (10.1.0.0/16) |
| `vpc-peering.tf` | VPC peering between regions |
| `eks-west.tf` | West region EKS cluster |
| `gg9-helm-west.tf` | West region GridGain Helm release |
| `gg9-values-west.yaml` | West region Helm values |
| `outputs-dcr.tf` | Multi-region outputs |
| `setup-dcr.sh` | DCR setup using pod IPs |
| `setup-dcr-tgw.sh` | DCR setup using client service endpoints |

To use DCR, copy these files to your root Terraform directory alongside the main cluster files.

## Troubleshooting

### Connection Failed

1. Verify network connectivity: `curl -v telnet://<endpoint>:10800`
2. Check security groups allow port 10800
3. Verify route tables have routes to peer VPC

### Schema Mismatch

Tables must have identical schemas on both clusters.
