// /api/ideas/list → GET returns all ideas (newest first).
// Thin alias over the GET branch of submit.js.
const submit = require('./submit.js');

module.exports = (req, res) => {
  req.method = 'GET';
  return submit(req, res);
};
