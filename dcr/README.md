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
│                              us-east-1                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         EKS Cluster (East)                             │ │
│  │   ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │   │  GridGain 9 (3 nodes)                                            │ │ │
│  │   │  gg9-0: 10.0.1.50    gg9-1: 10.0.2.51    gg9-2: 10.0.3.52       │ │ │
│  │   └──────────────────────────────────────────────────────────────────┘ │ │
│  │   ┌──────────────────────┐                                             │ │
│  │   │ Client Service (NLB) │ ← gg9-gridgain9-client:10800               │ │
│  │   └──────────────────────┘                                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │  DCR Replication
                         ┌────────────┴────────────┐
                         │   VPC Peering    OR     │
                         │   Transit Gateway       │
                         └────────────┬────────────┘
                                      │
┌─────────────────────────────────────│───────────────────────────────────────┐
│                              us-west-2                                       │
│  ┌──────────────────────────────────│─────────────────────────────────────┐ │
│  │                         EKS Cluster (West)                             │ │
│  │   ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │   │  GridGain 9 (3 nodes)                                            │ │ │
│  │   │  gg9-0: 10.1.1.50    gg9-1: 10.1.2.51    gg9-2: 10.1.3.52       │ │ │
│  │   └──────────────────────────────────────────────────────────────────┘ │ │
│  │   ┌──────────────────────┐                                             │ │
│  │   │ Client Service (NLB) │ ← gg9-west-gridgain9-client:10800          │ │
│  │   └──────────────────────┘                                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Network Connectivity Options

DCR requires network connectivity between clusters on port **10800** (thin client protocol). Choose based on your requirements:

### Option A: VPC Peering

Best for simple two-region deployments.

| Pros | Cons |
|------|------|
| Free (data transfer only) | 1:1 connections only |
| Lower latency | No transitive routing |
| Simple setup | Doesn't scale beyond 2 VPCs |

**Setup:**
1. Create VPC peering connection between regions
2. Accept peering in destination region
3. Add routes to both VPC route tables
4. Update security groups to allow port 10800

```hcl
# See vpc-peering.tf for full example
resource "aws_vpc_peering_connection" "east_west" {
  vpc_id      = module.vpc_east.vpc_id
  peer_vpc_id = module.vpc_west.vpc_id
  peer_region = "us-west-2"
}
```

### Option B: Transit Gateway

Best for enterprise deployments with multiple VPCs or on-prem connectivity.

| Pros | Cons |
|------|------|
| Hub-and-spoke (scales to 5000+ VPCs) | ~$0.05/hr per attachment |
| Transitive routing | Slightly higher latency |
| Centralized routing tables | More complex setup |
| On-prem connectivity via VPN/DX | |

**Setup:**
1. Create Transit Gateway in each region
2. Create TGW peering between regions
3. Attach VPCs to their regional TGW
4. Configure route tables

```hcl
# Transit Gateway in each region
resource "aws_ec2_transit_gateway" "east" {
  description = "GridGain DCR - East"
  dns_support = "enable"
}

resource "aws_ec2_transit_gateway" "west" {
  provider    = aws.west
  description = "GridGain DCR - West"
  dns_support = "enable"
}

# TGW Peering
resource "aws_ec2_transit_gateway_peering_attachment" "east_west" {
  transit_gateway_id      = aws_ec2_transit_gateway.east.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.west.id
  peer_region             = "us-west-2"
}
```

## DCR Endpoint Options

The Helm chart creates a client LoadBalancer service for external access. You can use either:

### Option 1: Pod IPs (Direct)

Connect DCR directly to pod IPs. Lower latency but IPs change on pod restart.

```bash
# Get pod IPs
kubectl get pods -n gridgain -o wide

# Example DCR source addresses:
# 10.0.1.50:10800,10.0.2.51:10800,10.0.3.52:10800
```

**Best for:**
- VPC peering deployments
- Lower latency requirements
- Clusters where pods rarely restart

### Option 2: Client Service (NLB)

Connect DCR to the LoadBalancer service. Stable endpoint that survives pod restarts.

```bash
# Get client service endpoint
kubectl get svc gg9-gridgain9-client -n gridgain

# Example DCR source address:
# internal-abc123.elb.us-east-1.amazonaws.com:10800
```

**Best for:**
- Transit Gateway deployments
- Enterprise network requirements
- Stable, predictable endpoints

### Internal NLB for DCR

For Transit Gateway, configure internal NLBs in your Helm values:

```yaml
# gg9-values.yaml
services:
  client:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    ports:
      rest: 10800
```

## Security Group Configuration

Allow DCR traffic between VPCs:

```hcl
# Allow West VPC to reach East cluster
resource "aws_security_group_rule" "east_allow_west_dcr" {
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = ["10.1.0.0/16"]  # West VPC CIDR
  security_group_id = module.eks.node_security_group_id
  description       = "DCR from West VPC"
}

# Allow East VPC to reach West cluster
resource "aws_security_group_rule" "west_allow_east_dcr" {
  provider          = aws.west
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # East VPC CIDR
  security_group_id = module.eks_west.node_security_group_id
  description       = "DCR from East VPC"
}
```

## Configuring DCR

### Prerequisites

1. Both clusters deployed and healthy
2. Network connectivity verified (port 10800)
3. Same table schema on both clusters

### Step 1: Create Tables on Both Clusters

Tables must exist on both clusters before enabling DCR:

```sql
-- Run on BOTH clusters
CREATE TABLE IF NOT EXISTS Customers (
  Id INT PRIMARY KEY,
  Name VARCHAR,
  Email VARCHAR
);

CREATE TABLE IF NOT EXISTS Products (
  Id INT PRIMARY KEY,
  Name VARCHAR,
  Price DECIMAL
);
```

### Step 2: Configure DCR Channels

DCR is configured on the **receiver** cluster, pointing to the **source** cluster.

**East → West (configured on West):**

```bash
# Get source endpoint (East cluster)
EAST_ENDPOINT="internal-east-nlb.elb.us-east-1.amazonaws.com:10800"

# On West cluster, create DCR channel
kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr create \
    --name east-to-west \
    --source-cluster-address $EAST_ENDPOINT \
    --username admin \
    --password <password>

# Start replication for all tables in PUBLIC schema
kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr start \
    --name east-to-west \
    --schema=PUBLIC \
    --all
```

**West → East (configured on East):**

```bash
# Get source endpoint (West cluster)
WEST_ENDPOINT="internal-west-nlb.elb.us-west-2.amazonaws.com:10800"

# On East cluster, create DCR channel
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr create \
    --name west-to-east \
    --source-cluster-address $WEST_ENDPOINT \
    --username admin \
    --password <password>

# Start replication
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 dcr start \
    --name west-to-east \
    --schema=PUBLIC \
    --all
```

### Step 3: Verify Replication

```bash
# Insert data on East
kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql \
  "INSERT INTO Customers VALUES (1, 'John Doe', 'john@example.com')"

# Verify on West (after a few seconds)
kubectl exec -it gg9-west-gridgain9-0 -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql \
  "SELECT * FROM Customers"
```

### DCR Commands Reference

```bash
# List DCR channels
gridgain9 dcr list

# Check DCR status
gridgain9 dcr status --name east-to-west

# Stop replication
gridgain9 dcr stop --name east-to-west --all

# Delete DCR channel
gridgain9 dcr delete --name east-to-west
```

## Automation Scripts

See the `scripts/` directory for automation:

| Script | Description |
|--------|-------------|
| `setup-dcr.sh` | Configure DCR using pod IPs (VPC peering) |
| `setup-dcr-tgw.sh` | Configure DCR using NLB endpoints (Transit Gateway) |

## Troubleshooting

### DCR Connection Failed

1. **Verify network connectivity:**
   ```bash
   kubectl exec -it gg9-gridgain9-0 -n gridgain -- \
     curl -v telnet://<remote-endpoint>:10800
   ```

2. **Check security groups** allow port 10800 between VPCs

3. **Verify route tables** have routes to the peer VPC

### Replication Lag

1. **Check DCR status:**
   ```bash
   gridgain9 dcr status --name east-to-west
   ```

2. **Monitor network latency** between regions

3. **Check cluster health** on both sides

### Schema Mismatch

Tables must have identical schemas on both clusters. DCR will fail if schemas differ.

```bash
# Compare schemas
gridgain9 sql "DESCRIBE Customers"  # Run on both clusters
```

## Best Practices

1. **Use internal NLBs** for DCR traffic (not public endpoints)
2. **Monitor replication lag** with GridGain metrics
3. **Test failover procedures** regularly
4. **Use non-overlapping VPC CIDRs** (e.g., 10.0.0.0/16 and 10.1.0.0/16)
5. **Enable DNS resolution** on VPC peering for hostname resolution
