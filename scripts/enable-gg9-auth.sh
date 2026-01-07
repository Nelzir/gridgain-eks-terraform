#!/usr/bin/env bash
set -euo pipefail

# =========================
# Enable GridGain 9 Authentication
# Run after cluster is initialized
# =========================

NAMESPACE="${NAMESPACE:-gridgain}"
CONTEXT="${CONTEXT:-gg9-eks}"
ADMIN_PASSWORD="${GG9_ADMIN_PASSWORD:-}"

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "Error: GG9_ADMIN_PASSWORD environment variable is required"
  exit 1
fi

echo "=== Enabling GridGain 9 Authentication ==="

# Get first pod
POD=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=gridgain9 -o jsonpath='{.items[0].metadata.name}')
echo "Using pod: $POD"

# Enable security on the cluster
echo "Enabling security..."
kubectl --context "$CONTEXT" -n "$NAMESPACE" exec -i "$POD" -- \
  /opt/gridgain9cli/bin/gridgain9 cluster config update \
  "ignite.security.enabled: true"

echo "Updating default admin password..."
kubectl --context "$CONTEXT" -n "$NAMESPACE" exec -i "$POD" -- \
  /opt/gridgain9cli/bin/gridgain9 cluster config update \
  "ignite.security.authentication.providers.default.users.ignite.password: \"$ADMIN_PASSWORD\""

echo ""
echo "=== Authentication Enabled ==="
echo "Default user: ignite"
echo "Password: (as provided)"
echo ""
echo "To connect with auth:"
echo "  gridgain9 connect http://<host>:10300 --username ignite --password <password>"
echo ""
echo "To create additional users, use SQL:"
echo "  CREATE USER myuser WITH PASSWORD 'mypassword';"
