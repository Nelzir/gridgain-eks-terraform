#!/usr/bin/env bash
set -euo pipefail

# =========================
# GridGain DCR Setup Script for Transit Gateway
# Uses internal NLB endpoints instead of pod IPs for stable routing
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =========================
# CONFIG
# =========================
NAMESPACE="gridgain"
EAST_CONTEXT="gg9-eks"
WEST_CONTEXT="gg9-eks-west"

# Service names (from Helm chart)
EAST_CLIENT_SVC="gg9-gridgain9-client"
WEST_CLIENT_SVC="gg9-west-gridgain9-client"

# GridGain credentials
GG_USERNAME="${GG_USERNAME:-admin}"
GG_PASSWORD="${GG_PASSWORD:-admin}"

# Replication configuration
DCR_EAST_TO_WEST="east-to-west"
DCR_WEST_TO_EAST="west-to-east"
REPL_SCHEMA="PUBLIC"

# =========================
# FUNCTIONS
# =========================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_first_pod() {
  local context="$1"
  kubectl --context "$context" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

get_nlb_endpoint() {
  local context="$1"
  local svc_name="$2"
  local port="${3:-10800}"
  
  # Get the LoadBalancer hostname or IP
  local endpoint
  endpoint=$(kubectl --context "$context" -n "$NAMESPACE" get svc "$svc_name" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  
  # If no hostname, try IP (for internal NLBs)
  if [ -z "$endpoint" ]; then
    endpoint=$(kubectl --context "$context" -n "$NAMESPACE" get svc "$svc_name" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  fi
  
  if [ -z "$endpoint" ]; then
    log_error "Could not get endpoint for service $svc_name in context $context"
    return 1
  fi
  
  echo "${endpoint}:${port}"
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
echo "GridGain DCR Setup - Transit Gateway Mode"
echo "Using NLB endpoints for stable routing"
echo "=========================================="
echo ""

# Get pod names for CLI execution
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

# Get NLB endpoints
log_info "Getting NLB endpoints..."
EAST_ENDPOINT=$(get_nlb_endpoint "$EAST_CONTEXT" "$EAST_CLIENT_SVC")
WEST_ENDPOINT=$(get_nlb_endpoint "$WEST_CONTEXT" "$WEST_CLIENT_SVC")

log_info "East NLB endpoint: $EAST_ENDPOINT"
log_info "West NLB endpoint: $WEST_ENDPOINT"

echo ""
echo "=========================================="
echo "Creating Tables on West (for DCR replication)"
echo "=========================================="
echo ""

log_info "Creating Customers table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Customers (Id INT PRIMARY KEY, Name VARCHAR, Email VARCHAR)" || true

log_info "Creating Products table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Products (Id INT PRIMARY KEY, Name VARCHAR, Price DECIMAL)" || true

log_info "Creating Orders table on West cluster (colocated by CustomerId)..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS Orders (CustomerId INT, Id INT, ProductId INT, Quantity INT, OrderDate TIMESTAMP, PRIMARY KEY (CustomerId, Id)) COLOCATE BY (CustomerId)" || true

log_info "Creating index on Orders.ProductId..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE INDEX IF NOT EXISTS idx_orders_productid ON Orders (ProductId)" || true

log_info "Creating PEOPLE table on East cluster..."
run_sql "$EAST_CONTEXT" "$EAST_POD" "CREATE TABLE IF NOT EXISTS people (id INT PRIMARY KEY, first_name VARCHAR, last_name VARCHAR)" || true

log_info "Creating PEOPLE table on West cluster..."
run_sql "$WEST_CONTEXT" "$WEST_POD" "CREATE TABLE IF NOT EXISTS people (id INT PRIMARY KEY, first_name VARCHAR, last_name VARCHAR)" || true

echo ""
echo "=========================================="
echo "Setting up DCR via Transit Gateway"
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
# SETUP EAST → WEST (configured on West, source = East NLB)
# =========================
log_info "Configuring ${DCR_EAST_TO_WEST} on west cluster"
log_info "Source: ${EAST_ENDPOINT} (East NLB via Transit Gateway)"

run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr create --name ${DCR_EAST_TO_WEST} --source-cluster-address ${EAST_ENDPOINT} --username ${GG_USERNAME} --password ${GG_PASSWORD}" || true
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr list"
run_cli "$WEST_CONTEXT" "$WEST_POD" "dcr start --name ${DCR_EAST_TO_WEST} --schema=${REPL_SCHEMA} --all" || true

echo ""

# =========================
# SETUP WEST → EAST (configured on East, source = West NLB)
# =========================
log_info "Configuring ${DCR_WEST_TO_EAST} on east cluster"
log_info "Source: ${WEST_ENDPOINT} (West NLB via Transit Gateway)"

run_cli "$EAST_CONTEXT" "$EAST_POD" "dcr create --name ${DCR_WEST_TO_EAST} --source-cluster-address ${WEST_ENDPOINT} --username ${GG_USERNAME} --password ${GG_PASSWORD}" || true
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
echo "DCR Configuration Complete (Transit Gateway)"
echo "=========================================="
echo ""
log_info "East → West: ${DCR_EAST_TO_WEST}"
log_info "  Source: ${EAST_ENDPOINT}"
log_info "West → East: ${DCR_WEST_TO_EAST}"
log_info "  Source: ${WEST_ENDPOINT}"
echo ""
log_info "Using NLB endpoints for stable Transit Gateway routing"
log_info "Test table 'people' created with columns: id, first_name, last_name"
echo ""
