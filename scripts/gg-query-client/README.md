# GridGain Query Client

HTTP proxy for executing SQL queries against GridGain. Designed for k6 load testing.

## Quick Start

### Get the LoadBalancer URL

```bash
LB=$(kubectl --context gg9-eks get svc gg-query-client -n gridgain \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

### Run Sample Queries

```bash
curl http://$LB/health

curl -s -X POST "http://$LB/query" \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT * FROM Customers WHERE Id = 1"}'

curl -s -X POST "http://$LB/query" \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT * FROM Orders WHERE CustomerId = ?", "args": [42]}'

curl -s -X POST "http://$LB/query" \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) FROM Orders"}'
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/query` | POST | Execute SQL query |
| `/health` | GET | Health check |

## Query Request

```json
{
  "sql": "SELECT * FROM Customers WHERE Id = ?",
  "args": [1]
}
```

## Query Response

```json
{
  "columns": ["ID", "NAME", "EMAIL"],
  "rows": [[1, "Customer 1", "customer1@example.com"]],
  "latency": "6.5ms"
}
```

Error response:
```json
{
  "error": "table not found",
  "latency": "1.2ms"
}
```

## Performance Notes

| Query Type | Expected Latency |
|------------|------------------|
| Point lookup (`WHERE Id = ?`) | 5-15ms |
| Range query (`LIMIT 10`) | 10-30ms |
| Aggregate (`GROUP BY`) | 300-500ms |

Point lookups are fast. Aggregates with GROUP BY are slower due to distributed data shuffling.

## Build and Push

Build for ARM (Graviton):

```bash
cd ~/Documents/GitHub
docker buildx build \
  --platform linux/arm64 \
  -f gridgain-eks-terraform/scripts/gg-query-client/Dockerfile \
  -t nelzir/gg-query-client:latest \
  --push .
```

## Local Testing

```bash
kubectl --context gg9-eks port-forward svc/gg9-gridgain9-headless 10800:10800 -n gridgain
go run . -gg-host localhost -gg-port 10800
```

Then:

```bash
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT * FROM Customers LIMIT 5"}'
```

## k6 Load Testing

```bash
LB=$(kubectl --context gg9-eks get svc gg-query-client -n gridgain \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
k6 run -e QUERY_CLIENT_URL=http://$LB scripts/k6/load-test.js
```
