#!/usr/bin/env bash
set -euo pipefail

# =========================
# Insert Sample Data into SQL Server
# Run this AFTER DCR is set up so data replicates to both clusters
# =========================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Config - get from terraform outputs
SQLSERVER_IP=$(terraform output -raw sqlserver_private_ip 2>/dev/null || echo "")
SQLSERVER_USER="${SQLSERVER_USER:-admin}"
SQLSERVER_PASS=$(terraform output -raw sqlserver_password 2>/dev/null || echo "")
SQLSERVER_DB="${SQLSERVER_DB:-testdb}"

if [ -z "$SQLSERVER_IP" ]; then
  echo "Error: Could not get SQL Server IP from terraform output"
  echo "Make sure you're in the terraform directory and have applied the config"
  exit 1
fi

log_info "SQL Server: $SQLSERVER_IP"
log_info "Database: $SQLSERVER_DB"

# Use a pod to connect to SQL Server (since it's in private subnet)
NAMESPACE="gridgain"
CONTEXT="gg9-eks"

log_info "Inserting sample data via kubectl exec..."

# Create a temporary pod with sqlcmd
kubectl --context "$CONTEXT" run sqlcmd-temp --rm -it --restart=Never \
  --image=mcr.microsoft.com/mssql-tools \
  --command -- /opt/mssql-tools/bin/sqlcmd \
    -S "$SQLSERVER_IP" \
    -U "$SQLSERVER_USER" \
    -P "$SQLSERVER_PASS" \
    -d "$SQLSERVER_DB" \
    -Q "
      -- Insert Customers
      INSERT INTO Customers (Id, Name, Email) VALUES (1, 'Acme Corp', 'contact@acme.com');
      INSERT INTO Customers (Id, Name, Email) VALUES (2, 'TechStart Inc', 'info@techstart.io');
      INSERT INTO Customers (Id, Name, Email) VALUES (3, 'Global Services', 'sales@globalsvcs.com');
      
      -- Insert Products
      INSERT INTO Products (Id, Name, Price) VALUES (1, 'Widget A', 9.99);
      INSERT INTO Products (Id, Name, Price) VALUES (2, 'Widget B', 19.99);
      INSERT INTO Products (Id, Name, Price) VALUES (3, 'Widget C', 4.99);
      
      -- Insert Orders
      INSERT INTO Orders (Id, CustomerId, ProductId, Quantity, OrderDate) VALUES (1, 1, 1, 100, GETDATE());
      INSERT INTO Orders (Id, CustomerId, ProductId, Quantity, OrderDate) VALUES (2, 2, 2, 50, GETDATE());
      INSERT INTO Orders (Id, CustomerId, ProductId, Quantity, OrderDate) VALUES (3, 3, 3, 200, GETDATE());
      
      SELECT 'Sample data inserted successfully' AS Status;
    "

echo ""
log_info "Sample data inserted into SQL Server"
log_info "The sqlserver-sync service will automatically sync this data to GridGain"
log_info "DCR will replicate the data between East and West clusters"
echo ""
log_info "Verify with:"
echo "  kubectl --context gg9-eks exec -it gg9-gridgain9-0 -n gridgain -- /opt/gridgain9cli/bin/gridgain9 sql 'SELECT * FROM Customers'"
echo "  kubectl --context gg9-eks-west exec -it gg9-west-gridgain9-0 -n gridgain -- /opt/gridgain9cli/bin/gridgain9 sql 'SELECT * FROM Customers'"
