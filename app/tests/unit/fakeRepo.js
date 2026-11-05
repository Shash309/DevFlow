// In-memory stand-in for the PostgreSQL repository, used by unit tests
function createFakeRepo({ healthy = true } = {}) {
  let tasks = [];
  let nextId = 1;
  return {
    healthy,
    async ping() {
      if (!this.healthy) throw new Error('database down');
    },
    async list() {
      return tasks;
    },
    async get(id) {
      return tasks.find((t) => t.id === id) || null;
    },
    async create(title) {
      const task = { id: nextId++, title, done: false, createdAt: new Date().toISOString() };
      tasks.push(task);
      return task;
    },
    async setDone(id, done) {
      const task = tasks.find((t) => t.id === id);
      if (!task) return null;
      task.done = done;
      return task;
    },
    async remove(id) {
      const before = tasks.length;
      tasks = tasks.filter((t) => t.id !== id);
      return tasks.length < before;
    },
  };
}

module.exports = { createFakeRepo };
