#!/usr/bin/env bash
set -euo pipefail

# =========================
# SQL Server Setup Script
# Creates testdb database with Change Tracking enabled
# =========================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get SQL Server connection info from Terraform
SQLSERVER_IP=$(terraform output -raw sqlserver_private_ip 2>/dev/null || echo "")
SQLSERVER_PASS=$(terraform output -raw sqlserver_password 2>/dev/null || echo "Admin123!")

if [ -z "$SQLSERVER_IP" ]; then
  log_error "Could not get SQL Server IP from terraform output"
  log_info "Make sure you're in the terraform directory and have deployed"
  exit 1
fi

log_info "SQL Server IP: $SQLSERVER_IP"

# Check if we can reach SQL Server via the sync pod
NAMESPACE="gridgain"
CONTEXT="gg9-eks"
SYNC_POD=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=sqlserver-sync -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$SYNC_POD" ]; then
  log_error "Sync pod not found. Deploy with 'terraform apply' first."
  exit 1
fi

log_info "Using sync pod: $SYNC_POD"

# SQL Script to set up testdb
SQL_SCRIPT=$(cat <<'EOSQL'
-- Create database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'testdb')
BEGIN
    CREATE DATABASE testdb;
    PRINT 'Created database: testdb';
END
GO

USE testdb;
GO

-- Enable Change Tracking on database
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
BEGIN
    ALTER DATABASE testdb SET CHANGE_TRACKING = ON 
        (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);
    PRINT 'Enabled Change Tracking on testdb';
END
GO

-- Customers table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Customers')
BEGIN
    CREATE TABLE Customers (
        ID INT PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Email NVARCHAR(100)
    );
    ALTER TABLE Customers ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Customers';
END
GO

-- Products table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Products')
BEGIN
    CREATE TABLE Products (
        ID INT PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Price DECIMAL(10, 2)
    );
    ALTER TABLE Products ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Products';
END
GO

-- Orders table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Orders')
BEGIN
    CREATE TABLE Orders (
        ID INT PRIMARY KEY,
        CustomerID INT,
        ProductID INT,
        Quantity INT,
        OrderDate NVARCHAR(50)
    );
    ALTER TABLE Orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Orders';
END
GO

-- Insert sample data
IF NOT EXISTS (SELECT 1 FROM Customers)
BEGIN
    INSERT INTO Customers (ID, Name, Email) VALUES
        (1, 'John Doe', 'john@example.com');
    PRINT 'Inserted sample customer';
END
GO

IF NOT EXISTS (SELECT 1 FROM Products)
BEGIN
    INSERT INTO Products (ID, Name, Price) VALUES
        (1, 'Widget', 29.99);
    PRINT 'Inserted sample product';
END
GO

IF NOT EXISTS (SELECT 1 FROM Orders)
BEGIN
    INSERT INTO Orders (ID, CustomerID, ProductID, Quantity, OrderDate) VALUES
        (1, 1, 1, 10, '2026-01-07');
    PRINT 'Inserted sample order';
END
GO

PRINT 'SQL Server setup complete!';
GO
EOSQL
)

log_info "Connecting to SQL Server and running setup..."

# Use kubectl exec to run sqlcmd from a pod that can reach SQL Server
# We'll use the sync pod since it has network access

kubectl --context "$CONTEXT" -n "$NAMESPACE" exec -i "$SYNC_POD" -- sh -c "
cat > /tmp/setup.sql << 'EOF'
$SQL_SCRIPT
EOF

# Check if sqlcmd is available, if not use go-mssqldb via our app
if command -v sqlcmd &> /dev/null; then
  sqlcmd -S $SQLSERVER_IP,1433 -U sa -P '$SQLSERVER_PASS' -i /tmp/setup.sql -C
else
  echo 'sqlcmd not available in container - use RDP or SSM to run SQL directly'
  exit 1
fi
"

if [ $? -ne 0 ]; then
  log_info ""
  log_info "Alternative: Run SQL via SSM port forward + DataGrip/SSMS"
  log_info ""
  log_info "1. Start port forward:"
  log_info "   aws ssm start-session --target \$(terraform output -raw sqlserver_instance_id) \\"
  log_info "     --document-name AWS-StartPortForwardingSession \\"
  log_info "     --parameters '{\"portNumber\":[\"1433\"],\"localPortNumber\":[\"1433\"]}'"
  log_info ""
  log_info "2. Connect to localhost:1433 with sa / $SQLSERVER_PASS"
  log_info ""
  log_info "3. Run the SQL script from: scripts/setup-sqlserver.sql"
fi

echo ""
log_info "=== SQL Server Setup Complete ==="
echo ""
echo "Database: testdb"
echo "Tables with Change Tracking:"
echo "  - Customers (ID, Name, Email)"
echo "  - Products (ID, Name, Price)"
echo "  - Orders (ID, CustomerID, ProductID, Quantity, OrderDate)"
