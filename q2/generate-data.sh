#!/usr/bin/env bash
set -euo pipefail

# Fast data generation using the Go query client (HTTP) instead of kubectl exec
# Requires the gg-query-client LoadBalancer to be running

CONTEXT="${CONTEXT:-gg9-eks}"
NAMESPACE="${NAMESPACE:-gridgain}"

# Get LoadBalancer URL
LB=$(kubectl --context "$CONTEXT" get svc gg-query-client -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB" ]; then
  echo "Error: Could not get gg-query-client LoadBalancer hostname"
  exit 1
fi

QUERY_URL="http://$LB/query"
echo "Using query client at: $QUERY_URL"

run_sql() {
  local sql="$1"
  curl -s -X POST "$QUERY_URL" \
    -H "Content-Type: application/json" \
    -d "{\"sql\": $(echo "$sql" | jq -Rs .)}"
}

echo ""
echo "Generating Q2 test data..."
echo ""

echo "1/4 Q2_AdminUserPropertyDataElements (86 rows)..."
SQL=$(awk 'BEGIN {
  printf "INSERT INTO Q2_AdminUserPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType, IsGroupProperty, IsUserProperty, VersionAdded) VALUES ";
  for(i=1; i<=86; i++) {
    if(i>1) printf ",";
    printf "(%d, '\''Property%d'\'', '\''Property Long Name %d'\'', '\''BIT'\'', true, true, 4400)", i, i, i;
  }
}')
run_sql "$SQL" | jq -r '.latency // .error'

echo "2/4 Q2_SystemPropertyDataElements (669 rows)..."
SQL=$(awk 'BEGIN {
  printf "INSERT INTO Q2_SystemPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType) VALUES ";
  for(i=1; i<=669; i++) {
    if(i>1) printf ",";
    printf "(%d, '\''SysProperty%d'\'', '\''System Property %d'\'', '\''BIT'\'')", i, i, i;
  }
}')
run_sql "$SQL" | jq -r '.latency // .error'

echo "3/4 Q2_SystemPropertyData (874 rows)..."
SQL=$(awk 'BEGIN {
  printf "INSERT INTO Q2_SystemPropertyData (SystemPropertyDataID, UISourceID, ProductTypeID, ProductID, GroupID, HADE_ID, PropertyID, PropertyValue) VALUES ";
  for(i=1; i<=874; i++) {
    if(i>1) printf ",";
    propId = ((i-1) % 669) + 1;
    printf "(%d, 8, NULL, NULL, NULL, NULL, %d, '\''True'\'')", i, propId;
  }
}')
run_sql "$SQL" | jq -r '.latency // .error'

# Insert default/fallback rows with NULLs first (these match the OR IS NULL pattern)
echo "4a/5 Q2_AdminUserPropertyData - Default rows with NULLs (86 rows per level)..."

# System-wide defaults: all NULLs except UISourceID=8 (Weight=100, lowest priority)
echo "  System defaults (GroupID=NULL, FIID=NULL, UserID=NULL)..."
SQL=$(awk 'BEGIN {
  printf "INSERT INTO Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES ";
  for(i=1; i<=86; i++) {
    if(i>1) printf ",";
    printf "(%d, NULL, NULL, 8, NULL, %d, '\''False'\'', 100)", i, i;
  }
}')
run_sql "$SQL" | jq -r '.latency // .error'

# Group-level defaults for common groups (Weight=200)
echo "  Group defaults (FIID=NULL, UserID=NULL) for groups 1,6,7..."
for grp in 1 6 7; do
  SQL=$(awk -v grp=$grp 'BEGIN {
    base = 86 + (grp * 86);
    printf "INSERT INTO Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES ";
    for(i=1; i<=86; i++) {
      if(i>1) printf ",";
      printf "(%d, %d, NULL, 8, NULL, %d, '\''True'\'', 200)", base+i, grp, i;
    }
  }')
  run_sql "$SQL" | jq -r '.latency // .error'
done

# FIID-level defaults (Weight=250)
echo "  FIID defaults (UserID=NULL) for FIID=1..."
SQL=$(awk 'BEGIN {
  base = 500;
  printf "INSERT INTO Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES ";
  for(i=1; i<=86; i++) {
    if(i>1) printf ",";
    printf "(%d, NULL, 1, 8, NULL, %d, '\''True'\'', 250)", base+i, i;
  }
}')
run_sql "$SQL" | jq -r '.latency // .error'

echo ""
echo "4b/5 Q2_AdminUserPropertyData - User-specific rows (42,269 rows in 43 batches)..."
START_TIME=$(date +%s)

# Start IDs after the default rows
ID_OFFSET=1000

for batch in $(seq 0 42); do
  START=$((batch * 1000 + 1))
  END=$((START + 999))
  if [ $END -gt 42269 ]; then END=42269; fi
  if [ $START -gt 42269 ]; then break; fi
  
  SQL=$(awk -v start=$START -v end=$END -v offset=$ID_OFFSET 'BEGIN {
    printf "INSERT INTO Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES ";
    first=1;
    for(i=start; i<=end; i++) {
      if(!first) printf ",";
      first=0;
      id = offset + i;
      groupId = ((i-1) % 100) + 1;
      fiid = ((i-1) % 50) + 1;
      userId = ((i-1) % 5000) + 1;
      propId = ((i-1) % 86) + 1;
      weight = 300;  # User-specific rows have highest weight
      printf "(%d, %d, %d, 8, %d, %d, '\''True'\'', %d)", id, groupId, fiid, userId, propId, weight;
    }
  }')
  
  LATENCY=$(run_sql "$SQL" | jq -r '.latency // .error')
  echo "  Batch $((batch + 1))/43: rows $START-$END ($LATENCY)"
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo ""
echo "Bulk insert completed in ${ELAPSED}s"

echo ""
echo "Verifying counts..."
run_sql "SELECT 'Q2_AdminUserPropertyDataElements' as tbl, COUNT(*) as cnt FROM Q2_AdminUserPropertyDataElements UNION ALL SELECT 'Q2_SystemPropertyDataElements', COUNT(*) FROM Q2_SystemPropertyDataElements UNION ALL SELECT 'Q2_SystemPropertyData', COUNT(*) FROM Q2_SystemPropertyData UNION ALL SELECT 'Q2_AdminUserPropertyData', COUNT(*) FROM Q2_AdminUserPropertyData" | jq '.rows'

echo ""
echo "Done!"
