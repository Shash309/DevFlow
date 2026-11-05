const request = require('supertest');
const { createApp, escapeHtml } = require('../../src/app');
const { createFakeRepo } = require('./fakeRepo');

const config = { appEnv: 'unit-test', build: '42' };

describe('health endpoints', () => {
  it('GET /live is always UP', async () => {
    const app = createApp({ repo: createFakeRepo({ healthy: false }), config });
    const res = await request(app).get('/live');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('UP');
  });

  it('GET /health reports UP with metadata when the database is reachable', async () => {
    const app = createApp({ repo: createFakeRepo(), config });
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: 'UP', database: 'UP', environment: 'unit-test', build: '42' });
    expect(typeof res.body.uptimeSeconds).toBe('number');
  });

  it('GET /health returns 503 when the database is down', async () => {
    const app = createApp({ repo: createFakeRepo({ healthy: false }), config });
    const res = await request(app).get('/health');
    expect(res.status).toBe(503);
    expect(res.body).toMatchObject({ status: 'DOWN', database: 'DOWN' });
  });

  it('uses defaults when no config is given', async () => {
    const app = createApp({ repo: createFakeRepo() });
    const res = await request(app).get('/health');
    expect(res.body).toMatchObject({ environment: 'local', build: 'dev' });
  });
});

describe('home page', () => {
  it('shows the environment, build and tasks', async () => {
    const repo = createFakeRepo();
    await repo.create('Write tests');
    const done = await repo.create('Ship it');
    await repo.setDone(done.id, true);
    const res = await request(createApp({ repo, config })).get('/');
    expect(res.status).toBe(200);
    expect(res.text).toContain('unit-test');
    expect(res.text).toContain('Build #42');
    expect(res.text).toContain('Write tests');
    expect(res.text).toContain('class="done"');
  });

  it('escapes task titles', async () => {
    const repo = createFakeRepo();
    await repo.create('<script>alert(1)</script>');
    const res = await request(createApp({ repo, config })).get('/');
    expect(res.text).not.toContain('<script>alert(1)</script>');
    expect(res.text).toContain('&lt;script&gt;');
  });
});

describe('escapeHtml', () => {
  it('escapes all special characters', () => {
    expect(escapeHtml('<a href="x">\'&\'</a>')).toBe('&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
  });
});

describe('tasks API', () => {
  let app;
  beforeEach(() => {
    app = createApp({ repo: createFakeRepo(), config });
  });

  it('creates, lists, reads, updates and deletes a task', async () => {
    const created = await request(app).post('/api/tasks').send({ title: '  Learn Kubernetes  ' });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ id: 1, title: 'Learn Kubernetes', done: false });

    const list = await request(app).get('/api/tasks');
    expect(list.body).toHaveLength(1);

    const one = await request(app).get('/api/tasks/1');
    expect(one.body.title).toBe('Learn Kubernetes');

    const updated = await request(app).patch('/api/tasks/1').send({ done: true });
    expect(updated.status).toBe(200);
    expect(updated.body.done).toBe(true);

    expect((await request(app).delete('/api/tasks/1')).status).toBe(204);
    expect((await request(app).get('/api/tasks/1')).status).toBe(404);
  });

  it.each([[{}], [{ title: '' }], [{ title: '   ' }], [{ title: 5 }], [{ title: 'x'.repeat(201) }]])(
    'rejects invalid task %j',
    async (body) => {
      const res = await request(app).post('/api/tasks').send(body);
      expect(res.status).toBe(400);
    },
  );

  it('validates PATCH input', async () => {
    expect((await request(app).patch('/api/tasks/abc').send({ done: true })).status).toBe(400);
    expect((await request(app).patch('/api/tasks/1').send({ done: 'yes' })).status).toBe(400);
    expect((await request(app).patch('/api/tasks/99').send({ done: true })).status).toBe(404);
  });

  it('returns 404 for unknown or invalid ids', async () => {
    expect((await request(app).get('/api/tasks/0')).status).toBe(404);
    expect((await request(app).get('/api/tasks/99')).status).toBe(404);
    expect((await request(app).delete('/api/tasks/-1')).status).toBe(404);
    expect((await request(app).delete('/api/tasks/99')).status).toBe(404);
  });

  it('returns 404 JSON for unknown routes', async () => {
    const res = await request(app).get('/nope');
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('Not found');
  });

  it('returns 500 when the database throws', async () => {
    const repo = createFakeRepo();
    repo.list = async () => {
      throw new Error('boom');
    };
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    const res = await request(createApp({ repo, config })).get('/api/tasks');
    expect(res.status).toBe(500);
    expect(res.body.error).toBe('Internal server error');
    spy.mockRestore();
  });
});

describe('metrics', () => {
  it('exposes Prometheus metrics including request counts', async () => {
    const app = createApp({ repo: createFakeRepo(), config });
    await request(app).get('/api/tasks');
    await request(app).get('/does-not-exist');
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/plain');
    expect(res.text).toMatch(/devflow_http_requests_total\{[^}]*route="\/api\/tasks"[^}]*status="200"/);
    expect(res.text).toContain('route="unmatched"');
    expect(res.text).toContain('environment="unit-test"');
    expect(res.text).toContain('process_cpu_user_seconds_total');
    expect(res.text).toMatch(/devflow_app_info\{[^}]*build="42"[^}]*\} 1/);
  });
});
