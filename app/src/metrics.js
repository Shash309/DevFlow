const client = require('prom-client');

// One registry per app instance, so tests can create several apps without duplicate-metric errors
function createMetrics(labels) {
  const register = new client.Registry();
  register.setDefaultLabels(labels);
  client.collectDefaultMetrics({ register });

  const httpRequests = new client.Counter({
    name: 'devflow_http_requests_total',
    help: 'HTTP requests handled',
    labelNames: ['method', 'route', 'status'],
    registers: [register],
  });

  const httpDuration = new client.Histogram({
    name: 'devflow_http_request_duration_seconds',
    help: 'HTTP request duration',
    labelNames: ['method', 'route'],
    buckets: [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2],
    registers: [register],
  });

  // Constant 1, labelled with what is deployed: lets Grafana show which build runs in each environment
  const appInfo = new client.Gauge({
    name: 'devflow_app_info',
    help: 'Deployed version and build',
    labelNames: ['version', 'build'],
    registers: [register],
  });

  function setAppInfo(version, build) {
    appInfo.set({ version, build }, 1);
  }

  function middleware(req, res, next) {
    const end = httpDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
      httpRequests.inc({ method: req.method, route, status: res.statusCode });
      end({ method: req.method, route });
    });
    next();
  }

  return { register, middleware, setAppInfo };
}

module.exports = { createMetrics };
