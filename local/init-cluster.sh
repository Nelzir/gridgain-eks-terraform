#!/bin/bash
set -e

GG_HOST="gg9-node1"
GG_CLI="/opt/gridgain9cli/bin/gridgain9"

echo "Waiting for all GridGain nodes to be ready..."
sleep 15

echo "Initializing cluster with 3 nodes..."
$GG_CLI cluster init \
  --url http://$GG_HOST:10300 \
  --name local-cluster \
  --metastorage-group gg9-node1,gg9-node2,gg9-node3 || true

echo "Waiting for cluster to stabilize..."
sleep 10

run_sql() {
    echo "Executing: $1"
    $GG_CLI sql --url jdbc:ignite:thin://$GG_HOST:10800 "$1" || true
}

echo "Creating zone with RF=3 for full replication..."
run_sql "CREATE ZONE IF NOT EXISTS q2_zone WITH REPLICAS=3, PARTITIONS=25, STORAGE_PROFILES='aipersist'"

echo "Creating tables..."
run_sql "CREATE TABLE IF NOT EXISTS Q2_AdminUserPropertyDataElements (
    PropertyID INT PRIMARY KEY,
    PropertyName VARCHAR(80) NOT NULL,
    PropertyLongName VARCHAR(80) NOT NULL,
    PropertyDataType VARCHAR(3) NOT NULL,
    IsGroupProperty BOOLEAN NOT NULL,
    IsUserProperty BOOLEAN NOT NULL,
    VersionAdded INT
) WITH PRIMARY_ZONE='q2_zone'"

run_sql "CREATE TABLE IF NOT EXISTS Q2_AdminUserPropertyData (
    UserPropertyDataID INT PRIMARY KEY,
    GroupID INT,
    FIID INT,
    UISourceID INT,
    UserID INT,
    PropertyID INT NOT NULL,
    PropertyValue VARCHAR(50),
    Weight INT
) WITH PRIMARY_ZONE='q2_zone'"

run_sql "CREATE TABLE IF NOT EXISTS Q2_SystemPropertyDataElements (
    PropertyID INT PRIMARY KEY,
    PropertyName VARCHAR(80) NOT NULL,
    PropertyLongName VARCHAR(80) NOT NULL,
    PropertyDataType VARCHAR(3) NOT NULL
) WITH PRIMARY_ZONE='q2_zone'"

run_sql "CREATE TABLE IF NOT EXISTS Q2_SystemPropertyData (
    SystemPropertyDataID INT PRIMARY KEY,
    UISourceID INT,
    ProductTypeID SMALLINT,
    ProductID SMALLINT,
    GroupID INT,
    HADE_ID INT,
    PropertyID INT NOT NULL,
    PropertyValue VARCHAR(1024) NOT NULL
) WITH PRIMARY_ZONE='q2_zone'"

echo "Creating indexes..."
run_sql "CREATE INDEX IF NOT EXISTS idx_admin_propdata_propid ON Q2_AdminUserPropertyData (PropertyID)"
run_sql "CREATE INDEX IF NOT EXISTS idx_admin_propdata_groupid ON Q2_AdminUserPropertyData (GroupID)"
run_sql "CREATE INDEX IF NOT EXISTS idx_admin_propdata_fiid ON Q2_AdminUserPropertyData (FIID)"
run_sql "CREATE INDEX IF NOT EXISTS idx_admin_propdata_uisourceid ON Q2_AdminUserPropertyData (UISourceID)"
run_sql "CREATE INDEX IF NOT EXISTS idx_admin_propdata_userid ON Q2_AdminUserPropertyData (UserID)"
run_sql "CREATE INDEX IF NOT EXISTS idx_system_propdata_propid ON Q2_SystemPropertyData (PropertyID)"

echo "Checking cluster topology..."
curl -s http://$GG_HOST:10300/management/v1/cluster/topology/logical | head -20

echo "==================================="
echo "GridGain cluster setup complete!"
echo "3 nodes with RF=3 (full replication)"
echo "Connect via: jdbc:ignite:thin://localhost:10800"
echo "REST API: http://localhost:10300"
echo "==================================="
