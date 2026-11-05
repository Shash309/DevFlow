const express = require('express');
const { version } = require('../package.json');
const { createMetrics } = require('./metrics');

const MAX_TITLE_LENGTH = 200;

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function parseId(raw) {
  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function validTitle(title) {
  return typeof title === 'string' && title.trim().length > 0 && title.length <= MAX_TITLE_LENGTH;
}

// Wraps async route handlers so rejected promises reach the error handler
const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

function renderHome({ appEnv, build, tasks }) {
  const items = tasks
    .map((t) => `<li class="${t.done ? 'done' : ''}">${escapeHtml(t.title)}</li>`)
    .join('');
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>DevFlow - ${escapeHtml(appEnv)}</title>
<style>
  body { font-family: sans-serif; max-width: 640px; margin: 8vh auto; padding: 0 16px; }
  h1 { margin-bottom: 0 } .env { font-size: 1.4em; color: #2563eb } .meta { color: #666 }
  li.done { text-decoration: line-through; color: #888 }
  form { display: flex; gap: 8px; margin-top: 16px } input { flex: 1; padding: 6px }
</style></head>
<body>
  <h1>DevFlow Tasks</h1>
  <p class="env">Environment: <b>${escapeHtml(appEnv)}</b></p>
  <p class="meta">Version ${version} &middot; Build #${escapeHtml(build)} &middot; ${tasks.length} task(s) in this environment's database</p>
  <ul id="tasks">${items}</ul>
  <form id="add"><input id="title" maxlength="${MAX_TITLE_LENGTH}" placeholder="New task" required><button>Add</button></form>
  <script>
    document.getElementById('add').addEventListener('submit', async (e) => {
      e.preventDefault();
      await fetch('/api/tasks', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: document.getElementById('title').value }) });
      location.reload();
    });
  </script>
</body></html>`;
}

function createApp({ repo, config = {} }) {
  const appEnv = config.appEnv || 'local';
  const build = config.build || 'dev';
  const startedAt = Date.now();
  const metrics = createMetrics({ environment: appEnv });
  metrics.setAppInfo(version, build);

  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '10kb' }));
  app.use(metrics.middleware);

  app.get('/', wrap(async (_req, res) => {
    const tasks = await repo.list();
    res.send(renderHome({ appEnv, build, tasks }));
  }));

  // Liveness: the process is running. Does not check the database, so a DB outage does not restart pods.
  app.get('/live', (_req, res) => res.json({ status: 'UP' }));

  // Readiness: the app can serve traffic, which needs the database.
  app.get('/health', async (_req, res) => {
    let database = 'UP';
    try {
      await repo.ping();
    } catch {
      database = 'DOWN';
    }
    res.status(database === 'UP' ? 200 : 503).json({
      status: database === 'UP' ? 'UP' : 'DOWN',
      database,
      environment: appEnv,
      version,
      build,
      uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    });
  });

  app.get('/metrics', wrap(async (_req, res) => {
    res.set('Content-Type', metrics.register.contentType);
    res.send(await metrics.register.metrics());
  }));

  app.get('/api/tasks', wrap(async (_req, res) => {
    res.json(await repo.list());
  }));

  app.get('/api/tasks/:id', wrap(async (req, res) => {
    const id = parseId(req.params.id);
    const task = id && (await repo.get(id));
    if (!task) return res.status(404).json({ error: 'Task not found' });
    return res.json(task);
  }));

  app.post('/api/tasks', wrap(async (req, res) => {
    const title = req.body && req.body.title;
    if (!validTitle(title)) {
      return res.status(400).json({ error: `title is required (1-${MAX_TITLE_LENGTH} characters)` });
    }
    return res.status(201).json(await repo.create(title.trim()));
  }));

  app.patch('/api/tasks/:id', wrap(async (req, res) => {
    const id = parseId(req.params.id);
    const done = req.body && req.body.done;
    if (!id || typeof done !== 'boolean') {
      return res.status(400).json({ error: 'a valid id and a boolean "done" are required' });
    }
    const task = await repo.setDone(id, done);
    if (!task) return res.status(404).json({ error: 'Task not found' });
    return res.json(task);
  }));

  app.delete('/api/tasks/:id', wrap(async (req, res) => {
    const id = parseId(req.params.id);
    if (!id || !(await repo.remove(id))) return res.status(404).json({ error: 'Task not found' });
    return res.status(204).end();
  }));

  app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

  app.use((err, _req, res, _next) => {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}

module.exports = { createApp, escapeHtml };
