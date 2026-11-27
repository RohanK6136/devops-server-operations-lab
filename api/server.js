'use strict';

const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { createDatabaseStore } = require('./database');

const PORT = Number(process.env.PORT || 3000);
const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_PORT = Number(process.env.DB_PORT || 5432);
const startedAt = Date.now();
const requestStats = new Map();
const HISTOGRAM_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];
const MAX_EVENT_BODY_BYTES = 4096;

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store'
  });
  res.end(body);
}

function checkTcp(host = DB_HOST, port = DB_PORT, timeoutMs = 800) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    let settled = false;
    const finish = (ok) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
  });
}

function routeName(pathname) {
  if (pathname === '/health') return 'health';
  if (pathname === '/health/ready' || pathname === '/api/health') return 'readiness';
  if (pathname === '/api/info') return 'info';
  if (pathname === '/api/events') return 'events';
  return 'not_found';
}

function recordRequest(method, route, status, seconds) {
  const key = [method, route, status].join('|');
  const record = requestStats.get(key) || {
    method,
    route,
    status,
    count: 0,
    sum: 0,
    buckets: HISTOGRAM_BUCKETS.map(() => 0)
  };
  record.count += 1;
  record.sum += seconds;
  HISTOGRAM_BUCKETS.forEach((limit, index) => {
    if (seconds <= limit) record.buckets[index] += 1;
  });
  requestStats.set(key, record);
}

function escapeLabel(value) {
  return String(value)
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n');
}

function renderMetrics() {
  const lines = [
    '# HELP devops_lab_http_requests_total Total HTTP requests served by this process.',
    '# TYPE devops_lab_http_requests_total counter'
  ];

  for (const record of requestStats.values()) {
    lines.push(
      'devops_lab_http_requests_total{method="' + escapeLabel(record.method) +
      '",route="' + escapeLabel(record.route) +
      '",status="' + record.status + '"} ' + record.count
    );
  }

  lines.push(
    '# HELP devops_lab_http_request_duration_seconds HTTP request duration in seconds.',
    '# TYPE devops_lab_http_request_duration_seconds histogram'
  );

  for (const record of requestStats.values()) {
    HISTOGRAM_BUCKETS.forEach((limit, index) => {
      lines.push(
        'devops_lab_http_request_duration_seconds_bucket{method="' +
        escapeLabel(record.method) + '",route="' + escapeLabel(record.route) +
        '",status="' + record.status + '",le="' + limit + '"} ' +
        record.buckets[index]
      );
    });
    lines.push(
      'devops_lab_http_request_duration_seconds_bucket{method="' +
      escapeLabel(record.method) + '",route="' + escapeLabel(record.route) +
      '",status="' + record.status + '",le="+Inf"} ' + record.count
    );
    lines.push(
      'devops_lab_http_request_duration_seconds_sum{method="' +
      escapeLabel(record.method) + '",route="' + escapeLabel(record.route) +
      '",status="' + record.status + '"} ' + record.sum
    );
    lines.push(
      'devops_lab_http_request_duration_seconds_count{method="' +
      escapeLabel(record.method) + '",route="' + escapeLabel(record.route) +
      '",status="' + record.status + '"} ' + record.count
    );
  }

  lines.push(
    '# HELP devops_lab_process_uptime_seconds Process uptime in seconds.',
    '# TYPE devops_lab_process_uptime_seconds gauge',
    'devops_lab_process_uptime_seconds ' + process.uptime()
  );
  return lines.join('\n') + '\n';
}

async function readJsonBody(req, maxBytes = MAX_EVENT_BODY_BYTES) {
  const chunks = [];
  let totalBytes = 0;

  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (totalBytes > maxBytes) {
      const error = new Error('request_body_too_large');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }

  if (totalBytes === 0) {
    const error = new Error('request_body_required');
    error.statusCode = 400;
    throw error;
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    const error = new Error('invalid_json');
    error.statusCode = 400;
    throw error;
  }
}

function validateEvent(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { error: 'json_object_required' };
  }

  const eventType = typeof payload.eventType === 'string'
    ? payload.eventType.trim()
    : 'manual';
  const message = typeof payload.message === 'string' ? payload.message.trim() : '';
  const metadata = payload.metadata === undefined ? {} : payload.metadata;

  if (!/^[a-zA-Z0-9_-]{1,48}$/.test(eventType)) {
    return { error: 'event_type_must_be_1_to_48_letters_digits_underscores_or_hyphens' };
  }
  if (message.length < 1 || message.length > 500) {
    return { error: 'message_must_be_1_to_500_characters' };
  }
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
    return { error: 'metadata_must_be_a_json_object' };
  }

  return {
    value: {
      eventType: eventType.toLowerCase(),
      message,
      metadata
    }
  };
}

function createServer({ checkDependency = checkTcp, store = null } = {}) {
  return http.createServer(async (req, res) => {
    const started = process.hrtime.bigint();
    const url = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));
    const pathname = url.pathname;
    const route = routeName(pathname);

    res.once('finish', () => {
      if (pathname === '/metrics') return;
      const elapsed = Number(process.hrtime.bigint() - started) / 1e9;
      recordRequest(req.method || 'UNKNOWN', route, res.statusCode, elapsed);
    });

    if (req.method === 'GET' && pathname === '/metrics') {
      const body = renderMetrics();
      res.writeHead(200, {
        'content-type': 'text/plain; version=0.0.4; charset=utf-8',
        'content-length': Buffer.byteLength(body),
        'cache-control': 'no-store'
      });
      return res.end(body);
    }

    if (req.method === 'GET' && pathname === '/health') {
      return send(res, 200, {
        status: 'ok',
        service: 'devops-lab-api',
        uptimeSeconds: Math.floor(process.uptime())
      });
    }

    if (req.method === 'GET' &&
        (pathname === '/health/ready' || pathname === '/api/health')) {
      let dependencyReady = false;
      try {
        dependencyReady = store && typeof store.checkReady === 'function'
          ? await store.checkReady()
          : await checkDependency();
      } catch {
        dependencyReady = false;
      }
      return send(res, dependencyReady ? 200 : 503, {
        status: dependencyReady ? 'ready' : 'not_ready',
        service: 'devops-lab-api',
        dependencies: { postgresTcp: dependencyReady },
        checkedAt: new Date().toISOString()
      });
    }

    if (req.method === 'GET' && pathname === '/api/info') {
      return send(res, 200, {
        service: 'devops-lab-api',
        environment: process.env.NODE_ENV || 'development',
        hostname: os.hostname(),
        platform: process.platform,
        nodeVersion: process.version,
        database: store ? 'postgresql' : 'not_configured',
        uptimeSeconds: Math.floor(process.uptime()),
        startedAt: new Date(startedAt).toISOString()
      });
    }

    if ((req.method === 'GET' || req.method === 'POST') && pathname === '/api/events') {
      if (!store) {
        return send(res, 503, { error: 'database_not_configured' });
      }

      try {
        if (req.method === 'GET') {
          const events = await store.listEvents(url.searchParams.get('limit'));
          return send(res, 200, { count: events.length, events });
        }

        const contentType = String(req.headers['content-type'] || '').toLowerCase();
        if (!contentType.includes('application/json')) {
          return send(res, 415, { error: 'content_type_must_be_application_json' });
        }

        const payload = await readJsonBody(req);
        const validated = validateEvent(payload);
        if (validated.error) {
          return send(res, 400, { error: validated.error });
        }

        const event = await store.createEvent(validated.value);
        return send(res, 201, { event });
      } catch (error) {
        const status = Number.isInteger(error.statusCode) ? error.statusCode : 500;
        if (status >= 500) {
          console.error(JSON.stringify({
            level: 'error',
            event: 'database_event_request_failed',
            message: error.message
          }));
          return send(res, 500, { error: 'database_request_failed' });
        }
        return send(res, status, { error: error.message || 'invalid_request' });
      }
    }

    return send(res, 404, { error: 'not_found', path: pathname });
  });
}

if (require.main === module) {
  (async () => {
    const store = createDatabaseStore();
    await store.initialize();

    const server = createServer({ store });
    server.listen(PORT, '0.0.0.0', () => {
      console.log(JSON.stringify({
        level: 'info',
        event: 'server_started',
        port: PORT,
        database: 'postgresql'
      }));
    });

    let shuttingDown = false;
    const shutdown = async (signal) => {
      if (shuttingDown) return;
      shuttingDown = true;
      console.log(JSON.stringify({ level: 'info', event: 'shutdown', signal }));
      const forceExit = setTimeout(() => process.exit(1), 5000);
      forceExit.unref();

      server.close(async () => {
        try {
          await store.close();
          clearTimeout(forceExit);
          process.exit(0);
        } catch (error) {
          console.error(JSON.stringify({
            level: 'error',
            event: 'database_shutdown_failed',
            message: error.message
          }));
          process.exit(1);
        }
      });
    };

    for (const signal of ['SIGTERM', 'SIGINT']) {
      process.on(signal, () => shutdown(signal));
    }
  })().catch((error) => {
    console.error(JSON.stringify({
      level: 'fatal',
      event: 'startup_failed',
      message: error.message
    }));
    process.exit(1);
  });
}

module.exports = { createServer, checkTcp, renderMetrics, readJsonBody, validateEvent };
