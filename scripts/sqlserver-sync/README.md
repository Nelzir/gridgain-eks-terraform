# SQL Server to GridGain 9 Sync

Polls SQL Server using Change Tracking and syncs changes to GridGain 9.

## Architecture

```
SQL Server (Change Tracking) → sqlserver-sync → GridGain 9 → DCR → GridGain 9 West
```

## Build & Push

```bash
# Login to Docker Hub
docker login

# Build for ARM64 (Graviton nodes - recommended)
docker buildx build --platform linux/arm64 -t nelzir/sqlserver-sync:latest --push .

# Or build for AMD64
docker buildx build --platform linux/amd64 -t nelzir/sqlserver-sync:latest --push .

# Or multi-arch
docker buildx build --platform linux/amd64,linux/arm64 -t nelzir/sqlserver-sync:latest --push .
```

## Prerequisites

### Enable Change Tracking in SQL Server

```sql
-- Enable on database
ALTER DATABASE testdb SET CHANGE_TRACKING = ON 
  (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);

-- Enable on each table to sync
ALTER TABLE dbo.Orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
ALTER TABLE dbo.Customers ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
```

### Create matching table in GridGain

```sql
CREATE TABLE Orders (
  id INT PRIMARY KEY,
  customer_id INT,
  total DECIMAL(10,2),
  created_at TIMESTAMP
);
```

## Usage

### Run Locally

```bash
go build -o sqlserver-sync .

./sqlserver-sync \
  -sqlserver "sqlserver://admin:admin@<ec2-private-ip>:1433?database=testdb" \
  -gg-host "localhost" \
  -gg-port 10800 \
  -gg-user "admin" \
  -gg-password "admin" \
  -tables "Orders,Customers" \
  -interval 30s
```

### Run in Kubernetes

The sync pod is deployed automatically via Terraform (`sqlserver-sync.tf`).

```bash
# Check pod status
kubectl get pods -n gridgain -l app=sqlserver-sync

# View logs
kubectl logs -n gridgain -l app=sqlserver-sync -f
```

## Configuration

### Command Line Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-sqlserver` | (required) | SQL Server connection string |
| `-gg-host` | `localhost` | GridGain host |
| `-gg-port` | `10800` | GridGain client port |
| `-gg-user` | | GridGain username |
| `-gg-password` | | GridGain password |
| `-tables` | (required) | Comma-separated table list |
| `-interval` | `30s` | Poll interval (Go duration: `30s`, `1m`, `500ms`) |
| `-state-file` | `sync_state.json` | State file path |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SQLSERVER_CONN` | SQL Server connection string |
| `GRIDGAIN_USER` | GridGain username |
| `GRIDGAIN_PASSWORD` | GridGain password |
| `SYNC_TABLES` | Comma-separated table list |

## How It Works

1. **Initial Load**: On first run (no state file), performs full table sync
2. **Change Tracking**: Stores last sync version in `sync_state.json`
3. **Polling**: Every interval, queries `CHANGETABLE()` for changes since last version
4. **Apply Changes**: 
   - `I` (Insert) → Upsert to GridGain
   - `U` (Update) → Upsert to GridGain
   - `D` (Delete) → Delete from GridGain

## Kubernetes Manifests

Reference manifests in `k8s/` directory:

- `configmap.yaml` - Non-sensitive config (interval, tables, port)
- `secret.yaml` - Sensitive config (connection strings, passwords)
- `deployment.yaml` - Pod deployment

These are managed by Terraform in production (`sqlserver-sync.tf`).

## Credentials

Default for POC: `admin` / `admin` for both SQL Server and GridGain.

## Notes

- Assumes first column is primary key (named `id` or `Id`)
- POC only - production would need batching, retries, monitoring
- Sync pod runs in east cluster only (same VPC as SQL Server)
