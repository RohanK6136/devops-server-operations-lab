'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('./server');

async function withServer(t, options = {}) {
  const server = createServer(options);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return 'http://127.0.0.1:' + server.address().port;
}

function createFakeStore() {
  const events = [];
  return {
    async checkReady() {
      return true;
    },
    async createEvent(event) {
      const created = {
        id: events.length + 1,
        eventType: event.eventType,
        message: event.message,
        metadata: event.metadata,
        createdAt: new Date().toISOString()
      };
      events.unshift(created);
      return created;
    },
    async listEvents(limit = 25) {
      const safeLimit = Math.max(1, Math.min(100, Number.parseInt(limit, 10) || 25));
      return events.slice(0, safeLimit);
    }
  };
}

test('liveness endpoint reports process health without depending on PostgreSQL', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => false });
  const response = await fetch(baseUrl + '/health');
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.status, 'ok');
  assert.equal(payload.service, 'devops-lab-api');
});

test('readiness endpoint returns 503 when PostgreSQL is unreachable', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => false });
  const response = await fetch(baseUrl + '/health/ready');
  assert.equal(response.status, 503);
  const payload = await response.json();
  assert.equal(payload.status, 'not_ready');
  assert.equal(payload.dependencies.postgresTcp, false);
});

test('readiness endpoint returns ready when dependency is reachable', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  const response = await fetch(baseUrl + '/health/ready');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, 'ready');
});

test('readiness uses the real database store check when a store is injected', async (t) => {
  const store = createFakeStore();
  const baseUrl = await withServer(t, { store });
  const response = await fetch(baseUrl + '/health/ready');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).dependencies.postgresTcp, true);
});

test('metrics endpoint exposes bounded route labels and counters', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  await fetch(baseUrl + '/health');
  await fetch(baseUrl + '/missing-route-123');
  const response = await fetch(baseUrl + '/metrics');
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.match(body, /devops_lab_http_requests_total/);
  assert.match(body, /route="health"/);
  assert.match(body, /route="not_found"/);
  assert.doesNotMatch(body, /missing-route-123/);
});

test('request duration histogram buckets are cumulative and non-decreasing', async (t) => {
  const baseUrl = await withServer(t, { checkDependency: async () => true });
  await fetch(baseUrl + '/health');
  const body = await (await fetch(baseUrl + '/metrics')).text();
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

test('POST /api/events persists a validated event and GET returns it', async (t) => {
  const store = createFakeStore();
  const baseUrl = await withServer(t, { store });
  const response = await fetch(baseUrl + '/api/events', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      eventType: 'Backup-Drill',
      message: 'Smoke test event survives database backup and restore',
      metadata: { source: 'unit-test', purpose: 'backup-restore' }
    })
  });

  assert.equal(response.status, 201);
  const created = await response.json();
  assert.equal(created.event.eventType, 'backup-drill');
  assert.equal(created.event.message, 'Smoke test event survives database backup and restore');

  const listResponse = await fetch(baseUrl + '/api/events');
  assert.equal(listResponse.status, 200);
  const listed = await listResponse.json();
  assert.equal(listed.count, 1);
  assert.equal(listed.events[0].id, created.event.id);
  assert.equal(listed.events[0].metadata.purpose, 'backup-restore');
});

test('POST /api/events rejects invalid event fields', async (t) => {
  const baseUrl = await withServer(t, { store: createFakeStore() });
  const response = await fetch(baseUrl + '/api/events', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ eventType: 'bad event type', message: 'Hello' })
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, 'event_type_must_be_1_to_48_letters_digits_underscores_or_hyphens');
});

test('POST /api/events requires JSON content type', async (t) => {
  const baseUrl = await withServer(t, { store: createFakeStore() });
  const response = await fetch(baseUrl + '/api/events', {
    method: 'POST',
    body: 'message=hello'
  });
  assert.equal(response.status, 415);
});

test('event routes return 503 when the database store is not configured', async (t) => {
  const baseUrl = await withServer(t);
  const response = await fetch(baseUrl + '/api/events');
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'database_not_configured');
});

test('unknown routes return 404', async (t) => {
  const baseUrl = await withServer(t);
  const response = await fetch(baseUrl + '/missing');
  assert.equal(response.status, 404);
});
