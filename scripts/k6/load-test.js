import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const queryLatency = new Trend('query_latency_ms');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 VUs
    { duration: '1m', target: 10 },    // Stay at 10 VUs
    { duration: '30s', target: 50 },   // Ramp up to 50 VUs
    { duration: '2m', target: 50 },    // Stay at 50 VUs
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests under 500ms
    errors: ['rate<0.1'],              // Error rate under 10%
  },
};

// Get LB hostname from environment or use default
const BASE_URL = __ENV.QUERY_CLIENT_URL || 'http://localhost:8080';

// Sample queries to run
const queries = [
  { sql: 'SELECT * FROM Customers', args: [] },
  { sql: 'SELECT * FROM Products', args: [] },
  { sql: 'SELECT * FROM Orders', args: [] },
  { sql: 'SELECT * FROM Customers WHERE ID = ?', args: [1] },
  { sql: 'SELECT COUNT(*) FROM Orders', args: [] },
];

export default function () {
  // Pick a random query
  const query = queries[Math.floor(Math.random() * queries.length)];

  const payload = JSON.stringify(query);
  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  const startTime = Date.now();
  const res = http.post(`${BASE_URL}/query`, payload, params);
  const duration = Date.now() - startTime;

  // Record custom latency metric
  queryLatency.add(duration);

  // Check response
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'no error in response': (r) => {
      try {
        const body = JSON.parse(r.body);
        return !body.error;
      } catch {
        return false;
      }
    },
  });

  errorRate.add(!success);

  // Small delay between requests
  sleep(0.1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, opts) {
  const metrics = data.metrics;
  return `
=====================================
GridGain Load Test Results
=====================================

Requests:
  Total:    ${metrics.http_reqs?.values?.count || 0}
  Rate:     ${(metrics.http_reqs?.values?.rate || 0).toFixed(2)}/s

Latency (http_req_duration):
  Avg:      ${(metrics.http_req_duration?.values?.avg || 0).toFixed(2)}ms
  Min:      ${(metrics.http_req_duration?.values?.min || 0).toFixed(2)}ms
  Max:      ${(metrics.http_req_duration?.values?.max || 0).toFixed(2)}ms
  P95:      ${(metrics.http_req_duration?.values?.['p(95)'] || 0).toFixed(2)}ms
  P99:      ${(metrics.http_req_duration?.values?.['p(99)'] || 0).toFixed(2)}ms

Query Latency (query_latency_ms):
  Avg:      ${(metrics.query_latency_ms?.values?.avg || 0).toFixed(2)}ms
  P95:      ${(metrics.query_latency_ms?.values?.['p(95)'] || 0).toFixed(2)}ms

Errors:
  Rate:     ${((metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%

=====================================
`;
}
