const { Pool } = require('pg');

// Uses DATABASE_URL if set, otherwise the standard PGHOST / PGUSER / PGPASSWORD / PGDATABASE variables
function createPool(env = process.env) {
  return new Pool(env.DATABASE_URL ? { connectionString: env.DATABASE_URL } : {});
}

function toTask(row) {
  return { id: row.id, title: row.title, done: row.done, createdAt: row.created_at };
}

function createTaskRepository(pool) {
  return {
    async init() {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS tasks (
          id         SERIAL PRIMARY KEY,
          title      TEXT        NOT NULL,
          done       BOOLEAN     NOT NULL DEFAULT false,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )`);
    },

    async ping() {
      await pool.query('SELECT 1');
    },

    async list() {
      const { rows } = await pool.query('SELECT * FROM tasks ORDER BY id');
      return rows.map(toTask);
    },

    async get(id) {
      const { rows } = await pool.query('SELECT * FROM tasks WHERE id = $1', [id]);
      return rows[0] ? toTask(rows[0]) : null;
    },

    async create(title) {
      const { rows } = await pool.query('INSERT INTO tasks (title) VALUES ($1) RETURNING *', [title]);
      return toTask(rows[0]);
    },

    async setDone(id, done) {
      const { rows } = await pool.query('UPDATE tasks SET done = $2 WHERE id = $1 RETURNING *', [id, done]);
      return rows[0] ? toTask(rows[0]) : null;
    },

    async remove(id) {
      const { rowCount } = await pool.query('DELETE FROM tasks WHERE id = $1', [id]);
      return rowCount > 0;
    },
  };
}

module.exports = { createPool, createTaskRepository };
