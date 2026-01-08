#!/usr/bin/env bash
set -euo pipefail

# =========================
# Create matching tables in SQL Server and GridGain 9
# =========================

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Config
NAMESPACE="${NAMESPACE:-gridgain}"
CONTEXT="${CONTEXT:-gg9-eks}"
SQLSERVER_HOST="${SQLSERVER_HOST:-}"
SQLSERVER_USER="${SQLSERVER_USER:-syncuser}"
SQLSERVER_PASS="${SQLSERVER_PASS:-}"
SQLSERVER_DB="${SQLSERVER_DB:-SyncDemo}"

if [ -z "$SQLSERVER_HOST" ] || [ -z "$SQLSERVER_PASS" ]; then
  echo "Error: SQLSERVER_HOST and SQLSERVER_PASS are required"
  exit 1
fi

# Get GG9 pod
GG_POD=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 -o jsonpath='{.items[0].metadata.name}')
log_info "Using GridGain pod: $GG_POD"

# =========================
# SQL Server Setup
# =========================
log_info "Setting up SQL Server..."

# Create SQL script for SQL Server
SQL_SCRIPT=$(cat <<'EOF'
-- Create database if not exists
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SyncDemo')
BEGIN
    CREATE DATABASE SyncDemo;
END
GO

USE SyncDemo;
GO

-- Enable Change Tracking on database
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
BEGIN
    ALTER DATABASE SyncDemo SET CHANGE_TRACKING = ON 
        (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);
END
GO

-- Create Orders table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Orders')
BEGIN
    CREATE TABLE Orders (
        id INT PRIMARY KEY,
        customer_name NVARCHAR(100) NOT NULL,
        product NVARCHAR(100) NOT NULL,
        quantity INT NOT NULL,
        price DECIMAL(10, 2) NOT NULL,
        order_date DATETIME2 DEFAULT GETDATE(),
        status NVARCHAR(20) DEFAULT 'pending'
    );
    
    -- Enable Change Tracking on table
    ALTER TABLE Orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
END
GO

-- Create Customers table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Customers')
BEGIN
    CREATE TABLE Customers (
        id INT PRIMARY KEY,
        name NVARCHAR(100) NOT NULL,
        email NVARCHAR(100),
        phone NVARCHAR(20),
        created_at DATETIME2 DEFAULT GETDATE()
    );
    
    ALTER TABLE Customers ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
END
GO

-- Insert sample data
IF NOT EXISTS (SELECT 1 FROM Customers)
BEGIN
    INSERT INTO Customers (id, name, email, phone) VALUES
        (1, 'Acme Corp', 'contact@acme.com', '555-0100'),
        (2, 'TechStart Inc', 'info@techstart.io', '555-0200'),
        (3, 'Global Services', 'sales@globalsvcs.com', '555-0300');
END
GO

IF NOT EXISTS (SELECT 1 FROM Orders)
BEGIN
    INSERT INTO Orders (id, customer_name, product, quantity, price, status) VALUES
        (1, 'Acme Corp', 'Widget A', 100, 9.99, 'shipped'),
        (2, 'TechStart Inc', 'Widget B', 50, 19.99, 'pending'),
        (3, 'Global Services', 'Widget C', 200, 4.99, 'delivered');
END
GO

PRINT 'SQL Server setup complete';
GO
EOF
)

log_info "Creating database and tables in SQL Server..."
echo "$SQL_SCRIPT" | sqlcmd -S "$SQLSERVER_HOST,1433" -U "$SQLSERVER_USER" -P "$SQLSERVER_PASS" -C

# =========================
# GridGain 9 Setup
# =========================
log_info "Setting up GridGain 9..."

run_gg_sql() {
  local sql="$1"
  log_info "GG9 SQL: $sql"
  kubectl --context "$CONTEXT" -n "$NAMESPACE" exec -i "$GG_POD" -- \
    /opt/gridgain9cli/bin/gridgain9 sql "$sql" 2>/dev/null || true
}

# Create matching tables in GridGain (with colocation for efficient joins)
run_gg_sql "CREATE TABLE IF NOT EXISTS Customers (
    Id INT PRIMARY KEY,
    Name VARCHAR(100),
    Email VARCHAR(100)
)"

run_gg_sql "CREATE TABLE IF NOT EXISTS Products (
    Id INT PRIMARY KEY,
    Name VARCHAR(100),
    Price DECIMAL(10, 2)
)"

# Orders colocated by CustomerId for efficient customer-order joins
run_gg_sql "CREATE TABLE IF NOT EXISTS Orders (
    CustomerId INT,
    Id INT,
    ProductId INT,
    Quantity INT,
    OrderDate TIMESTAMP,
    PRIMARY KEY (CustomerId, Id)
) COLOCATE BY (CustomerId)"

run_gg_sql "CREATE INDEX IF NOT EXISTS idx_orders_productid ON Orders (ProductId)"

echo ""
log_info "=== Setup Complete ==="
echo ""
echo "GridGain tables created with colocation:"
echo "  - Customers (Id, Name, Email)"
echo "  - Products (Id, Name, Price)"
echo "  - Orders (CustomerId, Id, ProductId, Quantity, OrderDate) - COLOCATED BY CustomerId"
echo ""
echo "Run ./scripts/insert-sample-data.sh to load sample data via SQL Server sync"
