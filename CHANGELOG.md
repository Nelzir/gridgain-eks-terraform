# Changelog

## [Unreleased] - 2026-01-06

### Multi-Region EKS with VPC Peering & GridGain DCR

#### Infrastructure Changes

**New Files:**
- `vpc-east.tf` - Dedicated VPC for us-east-1 (CIDR: 10.0.0.0/16)
- `vpc-west.tf` - VPC for us-west-2 (CIDR: 10.1.0.0/16)
- `vpc-peering.tf` - Cross-region VPC peering with route tables and security group rules
- `eks-west.tf` - Second EKS cluster in us-west-2 with identical node configuration
- `gg9-values-west.yaml` - Separate Helm values for west cluster (different cluster name)
- `scripts/setup-dcr.sh` - Script to configure bidirectional DCR between clusters

**Modified Files:**
- `main.tf` - Updated to use dedicated VPC instead of default VPC
- `gg9-helm.tf` - Added GridGain deployment for west cluster
- `gg9-values.yaml` - Switched to NVMe-only storage (removed EBS for RAFT logs)
- `outputs.tf` - Added outputs for both clusters and VPC peering
- `variables.tf` - No functional changes

#### Storage Architecture

Changed from hybrid storage to **NVMe-only**:
- **Before:** EBS (gp3) for RAFT logs/metastore + NVMe for data partitions
- **After:** All storage on local NVMe for maximum performance
- Durability via RAFT replication across 3 nodes

Updated paths in gg9-values.yaml:
```yaml
system {
  cmgPath = "/data/cmg"
  metastoragePath = "/data/metastorage"
  partitionsBasePath = "/data/partitions"
  partitionsLogPath = "/data/partitions-log"
}
```

#### Network Architecture

- **VPC Peering:** us-east-1 (10.0.0.0/16) ↔ us-west-2 (10.1.0.0/16)
- **No NAT Gateway:** Using public subnets with auto-assign public IPs (cost savings)
- **Security Groups:** Added rules to allow GridGain ports (10800, 3344) between VPCs
- **DCR Traffic:** Uses internal pod IPs via VPC peering (not public LoadBalancers)

#### Node Configuration

- **System nodes:** 1x m7g.medium per cluster (reduced from 2)
- **GridGain nodes:** 3x m7gd.2xlarge per cluster (Graviton with NVMe)

#### GridGain DCR Setup

The `scripts/setup-dcr.sh` script:
1. Creates test table: `people (id INT PRIMARY KEY, first_name VARCHAR, last_name VARCHAR)`
2. Configures bidirectional DCR using all pod IPs for redundancy
3. Uses internal pod IPs via VPC peering
4. Inserts test data and verifies replication

DCR connections:
- `east-to-west`: Configured on west cluster, replicates from east
- `west-to-east`: Configured on east cluster, replicates from west

#### Cluster Names

- East cluster: `gg9-gridgain9`
- West cluster: `gg9-west-gridgain9` (different name required for DCR)

---

### Commands

```bash
# Deploy infrastructure
terraform apply

# Setup DCR after clusters are running
./scripts/setup-dcr.sh

# Switch kubectl context
kubectl config use-context gg9-eks      # East
kubectl config use-context gg9-eks-west # West
```
