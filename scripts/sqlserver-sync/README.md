# SQL Server to GridGain 9 Sync

Simple Change Tracking-based sync from SQL Server to GridGain 9.

## Prerequisites

### Enable Change Tracking in SQL Server

```sql
-- Enable on database
ALTER DATABASE YourDB SET CHANGE_TRACKING = ON 
  (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);

-- Enable on each table to sync
ALTER TABLE dbo.YourTable ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
```

### Create matching table in GridGain

```sql
CREATE TABLE YourTable (
  id INT PRIMARY KEY,
  -- ... same columns as SQL Server
);
```

## Usage

```bash
# Build
go build -o sqlserver-sync .

# Run
./sqlserver-sync \
  -sqlserver "sqlserver://user:pass@host:1433?database=mydb" \
  -gg-host "gridgain.example.com" \
  -gg-port 10800 \
  -tables "Orders,Customers,Products" \
  -interval 30s
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SQLSERVER_CONN` | SQL Server connection string |
| `SYNC_TABLES` | Comma-separated table list |

## How It Works

1. On first run, performs full table load
2. Stores last sync version in `sync_state.json`
3. Polls `CHANGETABLE()` for inserts, updates, deletes since last version
4. Applies changes to GridGain using MERGE/DELETE

## Notes

- Assumes first column is primary key
- Uses the ggv9-go-client (GridGain 9 Go thin client)
- For POV only - production would need:
  - Batching for large changesets
  - Error handling and retries
  - Metrics/monitoring

## Dependencies

The go.mod uses a local replace directive for the GridGain client. Update for your environment:

```go
replace github.com/oscarmherrera/ggv9-go-client => /path/to/ggv9-go-client
```
