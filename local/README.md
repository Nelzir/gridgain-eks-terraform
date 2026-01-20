# Local End-to-End Development Environment

Full local setup with 3-node GridGain cluster, SQL Server, and sync service.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  gg9-node1  │────▶│  gg9-node2  │────▶│  gg9-node3  │
│  :10800     │◀────│  :10801     │◀────│  :10802     │
└─────────────┘     └─────────────┘     └─────────────┘
       ▲
       │ sync
       │
┌──────┴──────┐     ┌─────────────┐
│ sqlserver-  │◀────│  sqlserver  │
│    sync     │     │   :1433     │
└─────────────┘     └─────────────┘
```

## Quick Start

```bash
cd local

# Start everything
docker compose up -d

# Watch initialization
docker compose logs -f init sqlserver-init

# Once init completes, watch sync service
docker compose logs -f sqlserver-sync
```

## Endpoints

| Service | URL |
|---------|-----|
| GridGain JDBC | `jdbc:ignite:thin://localhost:10800` |
| GridGain REST | `http://localhost:10300` |
| SQL Server | `localhost:1433` (sa / YourStrong@Passw0rd) |

## Run Queries

```bash
# Interactive GridGain SQL shell
docker compose exec gg9-node1 /opt/gridgain9cli/bin/gridgain9 sql \
  --url jdbc:ignite:thin://localhost:10800

# Check row counts
docker compose exec gg9-node1 /opt/gridgain9cli/bin/gridgain9 sql \
  --url jdbc:ignite:thin://localhost:10800 \
  "SELECT 'Q2_AdminUserPropertyData' as tbl, COUNT(*) FROM Q2_AdminUserPropertyData"

# Run the full view query
docker compose exec gg9-node1 /opt/gridgain9cli/bin/gridgain9 sql \
  --url jdbc:ignite:thin://localhost:10800 \
  "$(cat ../q2/view-definition.sql | tail -n +10)"
```

## Test CDC Sync

```bash
# Insert a row in SQL Server
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d Q2Test \
  -Q "INSERT INTO admin.Q2_AdminUserPropertyData VALUES (100, 1, 1, 8, 999, 1, 'True', 100)"

# Wait for sync (10s interval)
sleep 15

# Verify in GridGain
docker compose exec gg9-node1 /opt/gridgain9cli/bin/gridgain9 sql \
  --url jdbc:ignite:thin://localhost:10800 \
  "SELECT * FROM Q2_AdminUserPropertyData WHERE UserPropertyDataID = 100"
```

## Cluster Management

```bash
# Check cluster state
curl http://localhost:10300/management/v1/cluster/state

# Check topology (3 nodes)
curl http://localhost:10300/management/v1/cluster/topology/logical

# Check sync service logs
docker compose logs -f sqlserver-sync

# Stop everything
docker compose down

# Stop and remove all data
docker compose down -v
```

## Rebuild After Code Changes

```bash
# Rebuild sync service
docker compose build sqlserver-sync

# Restart sync
docker compose up -d sqlserver-sync
```

## Differences from Production (EKS)

| Setting | Local | Production |
|---------|-------|------------|
| Nodes | 3 | 3 |
| Replicas | 3 | 3 |
| Memory/node | 2GB | 28GB |
| Storage | Docker volume | NVMe |
| SQL Server | Container | EC2 |
