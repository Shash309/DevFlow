const app = require('./app');

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`DevFlow app (${process.env.APP_ENV || 'local'}) listening on port ${PORT}`);
});
