#!/usr/bin/env bash
set -euo pipefail

# =========================
# GridGain DCR Setup Script for EKS
# Configures bidirectional replication between us-east-1 and us-west-2 clusters
# Uses internal pod IPs via VPC peering
# =========================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =========================
# CONFIG
# =========================
NAMESPACE="gridgain"
EAST_CONTEXT="gg9-eks"
WEST_CONTEXT="gg9-eks-west"

# Replication configuration
DCR_EAST_TO_WEST="east-to-west"
DCR_WEST_TO_EAST="west-to-east"
REPL_SCHEMA="PUBLIC"

# =========================
# FUNCTIONS
# =========================
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

get_pods() {
  local context="$1"
  kubectl --context "$context" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

get_pod_ips() {
  local context="$1"
  kubectl --context "$context" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 --field-selector=status.phase=Running -o jsonpath='{.items[*].status.podIP}' 2>/dev/null
}

get_first_pod() {
  local context="$1"
  kubectl --context "$context" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Build comma-separated list of pod_ip:port for DCR source addresses
build_source_addresses() {
  local context="$1"
  local port="${2:-10800}"
  local ips=$(get_pod_ips "$context")
  local result=""
  for ip in $ips; do
    if [ -n "$result" ]; then
      result="${result},${ip}:${port}"
    else
      result="${ip}:${port}"
    fi
  done
  echo "$result"
}

run_cli() {
  local context="$1"
  local pod="$2"
  local cmd="$3"
  log_info "[$context/$pod] → $cmd"
  kubectl --context "$context" -n "$NAMESPACE" exec -i "$pod" -- /opt/gridgain9cli/bin/gridgain9 $cmd
}

run_sql() {
  local context="$1"
  local pod="$2"
  local sql="$3"
  log_info "[$context] SQL → $sql"
  kubectl --context "$context" -n "$NAMESPACE" exec -i "$pod" -- /opt/gridgain9cli/bin/gridgain9 sql "$sql"
}

# =========================
# MAIN
# =========================

echo "=========================================="
echo "GridGain DCR Setup - EKS Cross-Region"
echo "=========================================="
echo ""

# Get pod names
log_info "Finding GridGain pods..."
EAST_POD=$(get_first_pod "$EAST_CONTEXT")
WEST_POD=$(get_first_pod "$WEST_CONTEXT")

if [ -z "$EAST_POD" ]; then
  log_error "No GridGain pod found in east cluster ($EAST_CONTEXT)"
  exit 1
fi

if [ -z "$WEST_POD" ]; then
  log_error "No GridGain pod found in west cluster ($WEST_CONTEXT)"
  exit 1
fi

log_info "East pod: $EAST_POD"
log_info "West pod: $WEST_POD"

# Get all pod IPs for redundant connections
log_info "Getting pod IPs for all nodes..."
EAST_IPS=$(get_pod_ips "$EAST_CONTEXT")
WEST_IPS=$(get_pod_ips "$WEST_CONTEXT")

log_info "East pod IPs: $EAST_IPS"
log_info "West pod IPs: $WEST_IPS"

# Build source address lists
EAST_SOURCE_ADDRS=$(build_source_addresses "$EAST_CONTEXT")
WEST_SOURCE_ADDRS=$(build_source_addresses "$WEST_CONTEXT")

log_info "East source addresses: $EAST_SOURCE_ADDRS"
log_info "West source addresses: $WEST_SOURCE_ADDRS"

echo ""
echo "=========================================="
echo "Creating Tables on West (for DCR replication)"
echo "=========================================="
echo ""

# Create sync tables on West (must match East schema for DCR)
log_info "Creating Customers table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Customers (ID INT PRIMARY KEY, Name VARCHAR, Email VARCHAR)" || true

log_info "Creating Products table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Products (ID INT PRIMARY KEY, Name VARCHAR, Price DECIMAL)" || true

log_info "Creating Orders table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Orders (ID INT PRIMARY KEY, CustomerID INT, ProductID INT, Quantity INT, OrderDate VARCHAR)" || true

# Create test table on both clusters
log_info "Creating PEOPLE table on East cluster..."
run_sql "$EAST_CONTEXT" "$EAST_POD" "CREATE TABLE IF NOT EXISTS people (id INT PRIMARY KEY, first_name VARCHAR, last_name VARCHAR)" || true

log_info "Creating PEOPLE table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS people (id INT PRIMARY KEY, first_name VARCHAR, last_name VARCHAR)" || true

echo ""
echo "=========================================="
echo "Setting up DCR"
echo "=========================================="
echo ""

# Clean up existing DCR configs
log_info "Cleaning up existing DCR configs..."
run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr stop --name ${DCR_WEST_TO_EAST} --all" 2>/dev/null || true
run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr delete --name ${DCR_WEST_TO_EAST}" 2>/dev/null || true
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr stop --name ${DCR_EAST_TO_WEST} --all" 2>/dev/null || true
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr delete --name ${DCR_EAST_TO_WEST}" 2>/dev/null || true

echo ""

# =========================
# SETUP EAST → WEST (configured on West, source = East)
# =========================
log_info "Configuring ${DCR_EAST_TO_WEST} on west cluster"
log_info "Source addresses: ${EAST_SOURCE_ADDRS}"

run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr create --name ${DCR_EAST_TO_WEST} --source-cluster-address ${EAST_SOURCE_ADDRS}" || true
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr list"
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr start --name ${DCR_EAST_TO_WEST} --schema=${REPL_SCHEMA} --all" || true

echo ""

# =========================
# SETUP WEST → EAST (configured on East, source = West)
# =========================
log_info "Configuring ${DCR_WEST_TO_EAST} on east cluster"
log_info "Source addresses: ${WEST_SOURCE_ADDRS}"

run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr create --name ${DCR_WEST_TO_EAST} --source-cluster-address ${WEST_SOURCE_ADDRS}" || true
run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr list"
run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr start --name ${DCR_WEST_TO_EAST} --schema=${REPL_SCHEMA} --all" || true

echo ""
echo "=========================================="
echo "Inserting Test Data"
echo "=========================================="
echo ""

log_info "Inserting test data into East cluster..."
run_sql "$EAST_CONTEXT" "$EAST_POD" "INSERT INTO people VALUES (1, 'John', 'Doe')" || true

log_info "Inserting test data into West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "INSERT INTO people VALUES (2, 'Jane', 'Smith')" || true

echo ""
log_info "Waiting for replication..."
sleep 5

echo ""
echo "=========================================="
echo "Verifying Replication"
echo "=========================================="
echo ""

log_info "East cluster data:"
run_sql "$EAST_CONTEXT" "$EAST_POD" "SELECT * FROM people ORDER BY id"

echo ""
log_info "West cluster data:"
run_sql "$WEST_CONTEXT" "$WEST_POD" "SELECT * FROM people ORDER BY id"

echo ""
echo "=========================================="
echo "DCR Configuration Complete"
echo "=========================================="
echo ""
log_info "East → West: ${DCR_EAST_TO_WEST} (source: ${EAST_SOURCE_ADDRS})"
log_info "West → East: ${DCR_WEST_TO_EAST} (source: ${WEST_SOURCE_ADDRS})"
echo ""
log_info "Test table 'people' created with columns: id, first_name, last_name"
echo ""
