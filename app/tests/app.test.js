const request = require('supertest');
const app = require('../src/app');

describe('GET /health', () => {
  it('returns status UP with metadata', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('UP');
    expect(res.body).toHaveProperty('environment');
    expect(res.body).toHaveProperty('version');
    expect(typeof res.body.uptimeSeconds).toBe('number');
  });
});

describe('GET /', () => {
  it('renders the environment name', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.text).toContain('Environment:');
  });
});

describe('unknown routes', () => {
  it('return 404', async () => {
    const res = await request(app).get('/does-not-exist');
    expect(res.status).toBe(404);
  });
});
