#!/usr/bin/env bash
set -euo pipefail

# =========================
# Insert Sample Data into SQL Server via SSM
# Loads 1000 Customers, 500 Products, 10,000 Orders
# =========================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

cd "$(dirname "$0")/.."

INSTANCE_ID=$(terraform output -raw sqlserver_instance_id)
SQLSERVER_PASS=$(terraform output -raw sqlserver_password)

log_info "Loading sample data via SSM..."
log_info "  - 1,000 Customers"
log_info "  - 500 Products"
log_info "  - 10,000 Orders"
echo ""

# Use T-SQL WHILE loops for efficient batch insert (runs entirely on SQL Server)
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=[
    "$sqlcmd = \"C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\170\\Tools\\Binn\\SQLCMD.EXE\"",
    "$pass = \"'"${SQLSERVER_PASS}"'\"",
    "",
    "Write-Host \"Loading sample data...\"",
    "",
    "$sql = @\"",
    "USE testdb;",
    "DELETE FROM Orders; DELETE FROM Products; DELETE FROM Customers;",
    "",
    "-- Insert 1000 Customers",
    "DECLARE @i INT = 1;",
    "WHILE @i <= 1000 BEGIN",
    "  INSERT INTO Customers (Id, Name, Email) VALUES (@i, CONCAT('"'"'Customer '"'"', @i), CONCAT('"'"'customer'"'"', @i, '"'"'@example.com'"'"'));",
    "  SET @i = @i + 1;",
    "END;",
    "",
    "-- Insert 500 Products",
    "SET @i = 1;",
    "WHILE @i <= 500 BEGIN",
    "  INSERT INTO Products (Id, Name, Price) VALUES (@i, CONCAT('"'"'Product '"'"', @i), ROUND(RAND() * 100 + 10, 2));",
    "  SET @i = @i + 1;",
    "END;",
    "",
    "-- Insert 10000 Orders",
    "SET @i = 1;",
    "WHILE @i <= 10000 BEGIN",
    "  INSERT INTO Orders (Id, CustomerId, ProductId, Quantity, OrderDate) VALUES (@i, ((@i - 1) % 1000) + 1, ((@i - 1) % 500) + 1, (@i % 10) + 1, GETDATE());",
    "  SET @i = @i + 1;",
    "END;",
    "",
    "SELECT '"'"'Customers'"'"' AS T, COUNT(*) AS N FROM Customers UNION ALL SELECT '"'"'Products'"'"', COUNT(*) FROM Products UNION ALL SELECT '"'"'Orders'"'"', COUNT(*) FROM Orders;",
    "\"@",
    "",
    "& $sqlcmd -S localhost -U admin -P $pass -Q $sql",
    "",
    "Write-Host \"Done!\""
  ]' \
  --timeout-seconds 600 \
  --query 'Command.CommandId' --output text)

log_info "Command ID: $COMMAND_ID"
log_info "Running batch inserts on SQL Server (takes ~1-2 minutes)..."
echo ""

# Wait and poll for completion
for i in {1..24}; do
  sleep 10
  RESULT=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query '{Status:Status,Output:StandardOutputContent}' --output json 2>/dev/null || echo '{"Status":"Pending"}')
  
  STATUS=$(echo "$RESULT" | jq -r '.Status')
  
  if [ "$STATUS" = "Success" ]; then
    log_info "Sample data loaded successfully!"
    echo ""
    echo "$RESULT" | jq -r '.Output' | tail -20
    echo ""
    log_info "The sqlserver-sync pod will sync to GridGain within 30 seconds"
    log_info "Verify with:"
    echo "  kubectl --context gg9-eks exec gg9-gridgain9-0 -n gridgain -- /opt/gridgain9cli/bin/gridgain9 sql 'SELECT COUNT(*) FROM Orders'"
    exit 0
  elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ]; then
    log_warn "Command failed with status: $STATUS"
    echo "$RESULT" | jq -r '.Output'
    exit 1
  fi
  
  echo -n "."
done

log_warn "Timed out waiting for command. Check manually:"
echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID"
