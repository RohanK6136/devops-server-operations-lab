'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('./server');

async function withServer(t, options = {}) {
  const server = createServer(options);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return `http://127.0.0.1:${server.address().port}`;
}

test('liveness endpoint reports process health without depending on PostgreSQL', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => false });
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.status, 'ok');
  assert.equal(payload.service, 'devops-lab-api');
});

test('readiness endpoint returns 503 when PostgreSQL is unreachable', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => false });
  const response = await fetch(`${baseUrl}/health/ready`);
  assert.equal(response.status, 503);
  const payload = await response.json();
  assert.equal(payload.status, 'not_ready');
  assert.equal(payload.dependencies.postgresTcp, false);
});

test('readiness endpoint returns ready when dependency is reachable', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  const response = await fetch(`${baseUrl}/health/ready`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, 'ready');
});

test('metrics endpoint exposes bounded route labels and counters', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  await fetch(`${baseUrl}/health`);
  await fetch(`${baseUrl}/missing-route-123`);
  const response = await fetch(`${baseUrl}/metrics`);
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.match(body, /devops_lab_http_requests_total/);
  assert.match(body, /route="health"/);
  assert.match(body, /route="not_found"/);
  assert.doesNotMatch(body, /missing-route-123/);
});

test('request duration histogram buckets are cumulative and non-decreasing', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  await fetch(`${baseUrl}/health`);
  const body = await (await fetch(`${baseUrl}/metrics`)).text();
  const bucketLines = body.split('\n').filter((line) =>
    line.startsWith('devops_lab_http_request_duration_seconds_bucket{') &&
    line.includes('route="health"') && !line.includes('le="+Inf"')
  );
  const values = bucketLines.map((line) => Number(line.split(' ').at(-1)));
  assert.ok(values.length > 1);
  for (let index = 1; index < values.length; index += 1) {
    assert.ok(values[index] >= values[index - 1], 'Prometheus histogram buckets must be cumulative');
  }
});

test('unknown routes return 404', async (t) => {
  const baseUrl = await withServer(t);
  const response = await fetch(`${baseUrl}/missing`);
  assert.equal(response.status, 404);
});
