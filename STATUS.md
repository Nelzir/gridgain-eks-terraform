# Deployment Status

Last updated: 2026-01-08 00:10 UTC

## Current State: SQL Server Installation In Progress

### Infrastructure Deployed ✅

| Component | Status | Details |
|-----------|--------|---------|
| VPC East (us-east-1) | ✅ Deployed | 10.0.0.0/16 |
| VPC West (us-west-2) | ✅ Deployed | 10.1.0.0/16 |
| VPC Peering | ✅ Active | Cross-region connectivity |
| EKS East | ✅ Running | 3 GridGain nodes + 1 system node |
| EKS West | ✅ Running | 3 GridGain nodes + 1 system node |
| GridGain East | ✅ Running | 3 pods in `gridgain` namespace |
| GridGain West | ✅ Running | 3 pods in `gridgain` namespace |
| SQL Server EC2 | 🔄 Installing | i-0c603181a55fbd477 |
| Sync Pod | ✅ Deployed | Waiting for SQL Server |

### SQL Server Installation Progress

**Instance**: `i-0c603181a55fbd477`  
**Public IP**: `44.193.207.11`  
**Started**: 2026-01-07 23:44:30 UTC  
**Expected Completion**: ~00:05-00:15 UTC

#### Installation Steps
1. ✅ Windows Server 2022 booted (23:45:52 UTC)
2. 🔄 SQL Server 2022 ISO downloading (~1.5GB)
3. ⏳ SQL Server installation
4. ⏳ Admin login creation
5. ⏳ Firewall configuration

#### Monitoring Indicators
- **Instance Status**: OK
- **CPU Usage**: 58-91% (active installation)
- **Network In**: ~1.2GB downloaded (ISO nearly complete)

### Pending Tasks

1. **Wait for SQL Server install to complete** (~5-10 min)
2. **Verify SSM agent comes online**
3. **Run database setup script**:
   ```bash
   ./scripts/setup-sqlserver.sh
   ```
   Or manually via SSM port forward + DataGrip

4. **Load sample data**:
   ```bash
   # Via SSM port forward
   aws ssm start-session \
     --target $(terraform output -raw sqlserver_instance_id) \
     --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["1433"],"localPortNumber":["1433"]}'
   ```
   Then run `scripts/load-sample-data.sql` in DataGrip/SSMS

5. **Verify sync pod connects and syncs data**

6. **Setup DCR (Data Center Replication)**:
   ```bash
   ./scripts/setup-dcr.sh
   ```

### Connection Info

| Service | Access Method |
|---------|---------------|
| SQL Server | SSM port forward → localhost:1433 |
| GridGain East | `kubectl --context gg9-eks port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain` |
| GridGain West | `kubectl --context gg9-eks-west port-forward svc/gg9-west-gridgain9-headless 10801:10800 -n gridgain` |

### Useful Commands

```bash
# Check SQL Server install status (when SSM available)
aws ssm start-session --target i-0c603181a55fbd477

# Inside Windows, check install log:
# Get-Content C:\sqlserver-install.log -Tail 50

# Check CloudWatch metrics for install progress
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-0c603181a55fbd477 \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Average

# Check GridGain pods
kubectl --context gg9-eks get pods -n gridgain
kubectl --context gg9-eks-west get pods -n gridgain

# Check sync pod logs
kubectl --context gg9-eks -n gridgain logs -l app=sqlserver-sync -f
```

### AMI Creation

After SQL Server install completes, Terraform will automatically create an AMI for faster future deploys:

```bash
# Get created AMI ID
terraform output sqlserver_ami_id_created

# Add to terraform.tfvars for instant deploys
sqlserver_ami_id = "ami-xxxxxxxxxxxxxxxxx"
```
