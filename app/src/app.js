const express = require('express');
const { version } = require('../package.json');

const APP_ENV = process.env.APP_ENV || 'local';
const BUILD_NUMBER = process.env.BUILD_NUMBER || 'dev';
const startedAt = Date.now();

const app = express();

app.get('/', (req, res) => {
  res.send(`<!doctype html>
<html><head><title>DevFlow - ${APP_ENV}</title></head>
<body style="font-family:sans-serif;text-align:center;margin-top:15vh">
  <h1>DevFlow</h1>
  <h2>Environment: ${APP_ENV}</h2>
  <p>Version ${version} &middot; Build #${BUILD_NUMBER}</p>
</body></html>`);
});

app.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    environment: APP_ENV,
    version,
    build: BUILD_NUMBER,
    uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
  });
});

module.exports = app;
