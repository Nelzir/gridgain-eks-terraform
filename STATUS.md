# Deployment Status

Last updated: 2026-01-08 18:03 UTC

## Current State: ✅ Fully Operational

### Infrastructure

| Component | Status | Details |
|-----------|--------|---------|
| VPC East (us-east-1) | ✅ Deployed | 10.0.0.0/16 |
| VPC West (us-west-2) | ✅ Deployed | 10.1.0.0/16 |
| VPC Peering | ✅ Active | Cross-region connectivity |
| EKS East | ✅ Running | 3 GridGain nodes + 1 system node |
| EKS West | ✅ Running | 3 GridGain nodes + 1 system node |
| GridGain East | ✅ Running | 3 pods in `gridgain` namespace |
| GridGain West | ✅ Running | 3 pods in `gridgain` namespace |
| SQL Server | ✅ Running | i-0f11d60a8be6c6043 (t3.xlarge) |
| Sync Pod | ✅ Running | Syncing Orders, Customers, Products |

### SQL Server

- **Instance**: i-0f11d60a8be6c6043
- **Private IP**: 10.0.101.95
- **Public IP**: 35.170.51.72
- **Edition**: SQL Server 2022 Standard (AWS AMI)
- **Database**: testdb with Change Tracking enabled

### Synced Tables

| Table | Rows | Status |
|-------|------|--------|
| Customers | 1 | ✅ Synced |
| Products | 1 | ✅ Synced |
| Orders | 1 | ✅ Synced |

### Connection Info

| Service | Access Method |
|---------|---------------|
| SQL Server | SSM port forward → localhost:1433 |
| GridGain East | `kubectl --context gg9-eks port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain` |
| GridGain West | `kubectl --context gg9-eks-west port-forward svc/gg9-west-gridgain9-headless 10801:10800 -n gridgain` |

### Useful Commands

```bash
# Connect to SQL Server via SSM port forward
aws ssm start-session \
  --target $(terraform output -raw sqlserver_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["1433"],"localPortNumber":["1433"]}'

# Check GridGain pods
kubectl --context gg9-eks get pods -n gridgain
kubectl --context gg9-eks-west get pods -n gridgain

# Check sync pod logs
kubectl --context gg9-eks -n gridgain logs -l app=sqlserver-sync -f

# Query data in GridGain
kubectl --context gg9-eks -n gridgain exec gg9-gridgain9-0 -- \
  /opt/gridgain9cli/bin/gridgain9 sql "SELECT * FROM Customers"
```

### Next Steps

1. **Load more sample data** (optional):
   - Connect to SQL Server via SSM port forward
   - Run `scripts/load-sample-data.sql` to insert 1000 customers, 500 products, 10000 orders

2. **Setup DCR** (Data Center Replication):
   ```bash
   ./scripts/setup-dcr.sh
   ```
