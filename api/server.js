'use strict';

const http = require('node:http');
const net = require('node:net');
const os = require('node:os');

const PORT = Number(process.env.PORT || 3000);
const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_PORT = Number(process.env.DB_PORT || 5432);
const startedAt = Date.now();
const requestStats = new Map();
const HISTOGRAM_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];

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
  return 'not_found';
}

function recordRequest(method, route, status, seconds) {
  const key = `${method}|${route}|${status}`;
  const record = requestStats.get(key) || {
    method, route, status, count: 0, sum: 0,
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
  return String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
}

function renderMetrics() {
  const lines = [
    '# HELP devops_lab_http_requests_total Total HTTP requests served by this process.',
    '# TYPE devops_lab_http_requests_total counter',
  ];
  for (const record of requestStats.values()) {
    lines.push(`devops_lab_http_requests_total{method="${escapeLabel(record.method)}",route="${escapeLabel(record.route)}",status="${record.status}"} ${record.count}`);
  }
  lines.push(
    '# HELP devops_lab_http_request_duration_seconds HTTP request duration in seconds.',
    '# TYPE devops_lab_http_request_duration_seconds histogram'
  );
  for (const record of requestStats.values()) {
    // Buckets are recorded cumulatively in recordRequest, as required by Prometheus.
    HISTOGRAM_BUCKETS.forEach((limit, index) => {
      lines.push(`devops_lab_http_request_duration_seconds_bucket{method="${escapeLabel(record.method)}",route="${escapeLabel(record.route)}",status="${record.status}",le="${limit}"} ${record.buckets[index]}`);
    });
    lines.push(`devops_lab_http_request_duration_seconds_bucket{method="${escapeLabel(record.method)}",route="${escapeLabel(record.route)}",status="${record.status}",le="+Inf"} ${record.count}`);
    lines.push(`devops_lab_http_request_duration_seconds_sum{method="${escapeLabel(record.method)}",route="${escapeLabel(record.route)}",status="${record.status}"} ${record.sum}`);
    lines.push(`devops_lab_http_request_duration_seconds_count{method="${escapeLabel(record.method)}",route="${escapeLabel(record.route)}",status="${record.status}"} ${record.count}`);
  }
  lines.push(
    '# HELP devops_lab_process_uptime_seconds Process uptime in seconds.',
    '# TYPE devops_lab_process_uptime_seconds gauge',
    `devops_lab_process_uptime_seconds ${process.uptime()}`
  );
  return `${lines.join('\n')}\n`;
}

function createServer({ checkDependency = checkTcp } = {}) {
  return http.createServer(async (req, res) => {
    const started = process.hrtime.bigint();
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const pathname = url.pathname;
    const route = routeName(pathname);
    const finishMetric = () => {
      if (pathname === '/metrics') return;
      const elapsed = Number(process.hrtime.bigint() - started) / 1e9;
      recordRequest(req.method || 'UNKNOWN', route, res.statusCode, elapsed);
    };
    res.once('finish', finishMetric);

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

    if (req.method === 'GET' && (pathname === '/health/ready' || pathname === '/api/health')) {
      const dependencyReady = await checkDependency();
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
        uptimeSeconds: Math.floor(process.uptime()),
        startedAt: new Date(startedAt).toISOString()
      });
    }

    return send(res, 404, { error: 'not_found', path: pathname });
  });
}

if (require.main === module) {
  const server = createServer();
  server.listen(PORT, '0.0.0.0', () => {
    console.log(JSON.stringify({ level: 'info', event: 'server_started', port: PORT }));
  });
  for (const signal of ['SIGTERM', 'SIGINT']) {
    process.on(signal, () => {
      console.log(JSON.stringify({ level: 'info', event: 'shutdown', signal }));
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(1), 5000).unref();
    });
  }
}

module.exports = { createServer, checkTcp, renderMetrics };
