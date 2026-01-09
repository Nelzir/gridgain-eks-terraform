# Q2 Admin User Property View - GridGain Schema

Tables and queries for the Q2_AdminUserPropertyView POV testing.

## Files

| File | Description |
|------|-------------|
| tables.sql | GridGain table definitions with indexes |
| view-definition.sql | Equivalent query (GridGain doesn't support views) |
| sample-queries.sql | Common access patterns for k6 testing |
| sample-data.sql | Test data for performance testing |

## Tables

- **Q2_AdminUserPropertyDataElements** - Property definitions (lookup)
- **Q2_AdminUserPropertyData** - User/Group property values
- **Q2_SystemPropertyDataElements** - System property definitions
- **Q2_SystemPropertyData** - System property values

## Setup

```bash
GG_POD=$(kubectl --context gg9-eks get pods -n gridgain -l app.kubernetes.io/name=gridgain9 -o jsonpath='{.items[0].metadata.name}')

kubectl --context gg9-eks exec $GG_POD -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql "$(cat q2/tables.sql)"

kubectl --context gg9-eks exec $GG_POD -n gridgain -- \
  /opt/gridgain9cli/bin/gridgain9 sql "$(cat q2/sample-data.sql)"
```

## Test Query

```bash
LB=$(kubectl --context gg9-eks get svc gg-query-client -n gridgain \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -s -X POST "http://$LB/query" \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT aupd.UserPropertyDataID, aupd.GroupID, aupd.PropertyID, aupde.PropertyName, aupd.PropertyValue, aupd.Weight FROM Q2_AdminUserPropertyData aupd INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID WHERE (aupd.GroupID = ? OR aupd.GroupID IS NULL) AND (aupd.UserID = ? OR aupd.UserID IS NULL) ORDER BY aupd.PropertyID ASC, aupd.Weight DESC",
    "args": [7, 3]
  }'
```
