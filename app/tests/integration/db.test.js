// Runs against a real PostgreSQL. The pipeline starts a temporary one and sets DATABASE_URL.
const request = require('supertest');
const { createPool, createTaskRepository } = require('../../src/db');
const { createApp } = require('../../src/app');

const describeIfDb = process.env.DATABASE_URL ? describe : describe.skip;

describeIfDb('PostgreSQL integration', () => {
  let pool;
  let repo;

  beforeAll(async () => {
    pool = createPool();
    repo = createTaskRepository(pool);
    await repo.init();
    await repo.init(); // idempotent: safe to run on every start
  });

  beforeEach(async () => {
    await pool.query('TRUNCATE tasks RESTART IDENTITY');
  });

  afterAll(async () => {
    await pool.end();
  });

  it('pings the database', async () => {
    await expect(repo.ping()).resolves.toBeUndefined();
  });

  it('performs full CRUD on the tasks table', async () => {
    const task = await repo.create('Integration task');
    expect(task).toMatchObject({ id: 1, title: 'Integration task', done: false });
    expect(task.createdAt).toBeInstanceOf(Date);

    expect(await repo.list()).toHaveLength(1);
    expect((await repo.get(1)).title).toBe('Integration task');
    expect(await repo.get(999)).toBeNull();

    expect((await repo.setDone(1, true)).done).toBe(true);
    expect(await repo.setDone(999, true)).toBeNull();

    expect(await repo.remove(1)).toBe(true);
    expect(await repo.remove(1)).toBe(false);
    expect(await repo.list()).toHaveLength(0);
  });

  it('serves the API end to end with the real database', async () => {
    const app = createApp({ repo, config: { appEnv: 'integration' } });
    await request(app).post('/api/tasks').send({ title: 'via API' }).expect(201);
    const res = await request(app).get('/api/tasks').expect(200);
    expect(res.body.map((t) => t.title)).toEqual(['via API']);
    await request(app).get('/health').expect(200);
  });
});

describe('createPool', () => {
  it('uses DATABASE_URL when set, otherwise PG* variables', async () => {
    const withUrl = createPool({ DATABASE_URL: 'postgres://u:p@example:5432/db' });
    expect(withUrl.options.connectionString).toBe('postgres://u:p@example:5432/db');
    const withoutUrl = createPool({});
    expect(withoutUrl.options.connectionString).toBeUndefined();
    await Promise.all([withUrl.end(), withoutUrl.end()]);
  });
});
