const { createApp } = require('./app');
const { createPool, createTaskRepository } = require('./db');

const PORT = Number(process.env.PORT) || 3000;
const pool = createPool();
const repo = createTaskRepository(pool);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The database pod may start after the app pod, so retry instead of crashing
async function initDatabase(retries = 30) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await repo.init();
      return;
    } catch (err) {
      if (attempt >= retries) throw err;
      console.log(`Database not ready (${err.message}), retry ${attempt}/${retries}`);
      await sleep(2000);
    }
  }
}

async function main() {
  await initDatabase();
  const app = createApp({
    repo,
    config: { appEnv: process.env.APP_ENV, build: process.env.BUILD_NUMBER },
  });
  const server = app.listen(PORT, () => {
    console.log(`DevFlow (${process.env.APP_ENV || 'local'}) listening on port ${PORT}`);
  });

  // Kubernetes sends SIGTERM before stopping a pod: finish in-flight requests, then exit
  const shutdown = (signal) => {
    console.log(`${signal} received, shutting down`);
    server.close(() => pool.end().then(() => process.exit(0)));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err) => {
  console.error('Startup failed:', err);
  process.exit(1);
});
