import { appendFile } from 'node:fs/promises';
import http from 'node:http';

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1];
}

const port = Number(argument('--port', '18080'));
const output = argument('--output', 'requests.jsonl');
const statuses = argument('--statuses', '201').split(',').map(Number);
const maxRequests = Number(argument('--max-requests', String(statuses.length)));
let requestCount = 0;

const server = http.createServer((request, response) => {
  if (request.method === 'GET' && request.url === '/ready') {
    response.statusCode = 204;
    response.end();
    return;
  }

  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', async () => {
    requestCount += 1;
    await appendFile(output, `${JSON.stringify({
      method: request.method,
      url: request.url,
      authorization: request.headers.authorization,
      contentType: request.headers['content-type'],
      body: Buffer.concat(chunks).toString('utf8'),
    })}\n`);

    response.statusCode = statuses[Math.min(requestCount - 1, statuses.length - 1)];
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({ request: requestCount }));

    if (requestCount >= maxRequests) {
      setImmediate(() => server.close());
    }
  });
});

server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`roko mock listening on ${port}\n`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
