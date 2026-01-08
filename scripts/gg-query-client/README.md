# GridGain Query Client

HTTP proxy for executing SQL queries against GridGain. Designed for k6 load testing.

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/query` | POST | Execute SQL query |
| `/health` | GET | Health check |

## Query Request

```json
{
  "sql": "SELECT * FROM Customers WHERE ID = ?",
  "args": [1]
}
```

## Query Response

```json
{
  "columns": ["ID", "Name", "Email"],
  "rows": [[1, "John Doe", "john@example.com"]],
  "latency": "2.5ms"
}
```

Error response:
```json
{
  "error": "table not found",
  "latency": "1.2ms"
}
```

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
go run . -gg-host localhost -gg-port 10800
```

Then:

```bash
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT * FROM Customers"}'
```

## k6 Load Testing

After deploying to EKS:

```bash
# Get the LoadBalancer URL
LB_URL=$(kubectl --context gg9-eks get svc gg-query-client -n gridgain \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Run k6 test
k6 run -e QUERY_CLIENT_URL=http://$LB_URL scripts/k6/load-test.js
```
