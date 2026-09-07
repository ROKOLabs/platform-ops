import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const componentDirectory = path.dirname(testDirectory);
const shellCore = path.join(componentDirectory, 'core', 'roko-adapter.sh');
const powershellCore = path.join(componentDirectory, 'core', 'roko-adapter.ps1');
const coreKind = process.env.TEST_CORE || (process.platform === 'win32' ? 'powershell' : 'shell');

function cleanEnvironment(overrides = {}) {
  const environment = { ...process.env };
  for (const name of [
    'ROKO_ENDPOINT_URL',
    'ROKO_DEPLOY_TOKEN',
    'ROKO_ENVIRONMENT',
    'ROKO_SHA',
    'ROKO_DEPLOY_ID',
    'ROKO_STRICT',
  ]) {
    delete environment[name];
  }
  return { ...environment, ...overrides };
}

function runCore(arguments_, options = {}) {
  const command = coreKind === 'powershell' ? 'pwsh' : '/bin/sh';
  const commandArguments = coreKind === 'powershell'
    ? ['-NoLogo', '-NoProfile', '-File', powershellCore, ...arguments_]
    : [shellCore, ...arguments_];

  return new Promise((resolve) => {
    execFile(
      command,
      commandArguments,
      {
        cwd: options.cwd || componentDirectory,
        env: cleanEnvironment(options.env),
        timeout: 45_000,
      },
      (error, stdout, stderr) => {
        resolve({ code: error?.code ?? 0, stdout, stderr });
      },
    );
  });
}

async function startServer(statuses, responseBodies = []) {
  const requests = [];
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => {
      requests.push({
        method: request.method,
        url: request.url,
        authorization: request.headers.authorization,
        contentType: request.headers['content-type'],
        body: Buffer.concat(chunks).toString('utf8'),
      });
      const index = Math.min(requests.length - 1, statuses.length - 1);
      response.statusCode = statuses[index];
      response.setHeader('Content-Type', 'application/json');
      response.end(responseBodies[index] || JSON.stringify({ request: requests.length }));
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return {
    requests,
    url: `http://127.0.0.1:${address.port}/api/deploys`,
    close: () => new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    }),
  };
}

function baseArguments(url, additions = []) {
  return [
    'deploy',
    '--url', url,
    '--token', 'test-secret-token',
    '--environment', 'prod',
    '--sha', 'abc123',
    ...additions,
  ];
}

test(`${coreKind} core sends the exact deployment request`, async () => {
  const server = await startServer([201]);
  try {
    const result = await runCore(baseArguments(server.url, ['--deploy-id', '42']));

    assert.equal(result.code, 0);
    assert.match(result.stdout, /roko-adapter: reported abc123 to prod/);
    assert.equal(result.stderr, '');
    assert.deepEqual(server.requests, [{
      method: 'POST',
      url: '/api/deploys',
      authorization: 'Bearer test-secret-token',
      contentType: 'application/json',
      body: '{"environment":"prod","sha":"abc123","deployId":"42"}',
    }]);
  } finally {
    await server.close();
  }
});

test(`${coreKind} flags override environment variables and an empty deploy id is omitted`, async () => {
  const server = await startServer([204]);
  try {
    const result = await runCore(baseArguments(server.url, ['--deploy-id', '']), {
      env: {
        ROKO_ENDPOINT_URL: 'http://invalid.example',
        ROKO_DEPLOY_TOKEN: 'wrong-token',
        ROKO_ENVIRONMENT: 'staging',
        ROKO_SHA: 'wrong-sha',
        ROKO_DEPLOY_ID: 'wrong-id',
      },
    });

    assert.equal(result.code, 0);
    assert.equal(server.requests.length, 1);
    assert.equal(server.requests[0].body, '{"environment":"prod","sha":"abc123"}');
  } finally {
    await server.close();
  }
});

test(`${coreKind} core JSON-encodes deployment values`, async () => {
  const server = await startServer([201]);
  try {
    const result = await runCore([
      'deploy',
      '--url', server.url,
      '--token', 'test-secret-token',
      '--environment', 'production "blue"',
      '--sha', 'refs\\release',
      '--deploy-id', 'run\n2',
    ]);

    assert.equal(result.code, 0);
    assert.deepEqual(JSON.parse(server.requests[0].body), {
      environment: 'production "blue"',
      sha: 'refs\\release',
      deployId: 'run\n2',
    });
  } finally {
    await server.close();
  }
});

test(`${coreKind} core gets the SHA from the current git work tree`, async () => {
  const server = await startServer([200]);
  try {
    const result = await runCore([
      'deploy',
      '--url', server.url,
      '--token', 'test-secret-token',
      '--environment', 'prod',
    ]);
    const gitSha = await new Promise((resolve, reject) => {
      execFile('git', ['rev-parse', 'HEAD'], { cwd: componentDirectory }, (error, stdout) => {
        if (error) reject(error);
        else resolve(stdout.trim());
      });
    });

    assert.equal(result.code, 0);
    assert.equal(JSON.parse(server.requests[0].body).sha, gitSha);
  } finally {
    await server.close();
  }
});

test(`${coreKind} strict mode returns 2 when no SHA can be found`, async () => {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), 'roko-adapter-test-'));
  try {
    const result = await runCore([
      'deploy',
      '--url', 'http://127.0.0.1:1/api/deploys',
      '--token', 'test-secret-token',
      '--environment', 'prod',
      '--strict',
    ], { cwd: temporaryDirectory });

    assert.equal(result.code, 2);
    assert.match(result.stdout, /roko-adapter: missing sha/);
    assert.doesNotMatch(result.stdout + result.stderr, /test-secret-token/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test(`${coreKind} core retries retryable HTTP responses`, { timeout: 15_000 }, async () => {
  const server = await startServer([503, 503, 201]);
  try {
    const startedAt = Date.now();
    const result = await runCore(baseArguments(server.url));

    assert.equal(result.code, 0);
    assert.equal(server.requests.length, 3);
    assert.ok(Date.now() - startedAt >= 5_500, 'expected the 2s and 4s retry delays');
    assert.match(result.stdout, /attempt 1 failed with HTTP 503; retrying/);
    assert.match(result.stdout, /attempt 2 failed with HTTP 503; retrying/);
  } finally {
    await server.close();
  }
});

test(`${coreKind} strict mode returns 3 after retry exhaustion`, { timeout: 15_000 }, async () => {
  const server = await startServer([503, 503, 503]);
  try {
    const result = await runCore(baseArguments(server.url, ['--strict']));

    assert.equal(result.code, 3);
    assert.equal(server.requests.length, 3);
    assert.match(result.stdout, /warning: report failed after 3 attempts with HTTP 503/);
    assert.doesNotMatch(result.stdout + result.stderr, /test-secret-token/);
  } finally {
    await server.close();
  }
});

test(`${coreKind} core does not retry non-retryable HTTP responses`, async () => {
  const server = await startServer([409], ['deploy id already belongs to another commit']);
  try {
    const result = await runCore(baseArguments(server.url));

    assert.equal(result.code, 0);
    assert.equal(server.requests.length, 1);
    assert.match(result.stdout, /deploy id already belongs to another commit/);
  } finally {
    await server.close();
  }
});

test(`${coreKind} core redacts a token echoed by an error response`, async () => {
  const server = await startServer([401], ['test-secret-token']);
  try {
    const result = await runCore(baseArguments(server.url, ['--strict']));

    assert.equal(result.code, 3);
    assert.equal(server.requests.length, 1);
    assert.match(result.stdout, /\[redacted\]/);
    assert.doesNotMatch(result.stdout + result.stderr, /test-secret-token/);
  } finally {
    await server.close();
  }
});

test('shell core returns 4 in strict mode when curl is unavailable', {
  skip: coreKind !== 'shell',
}, async () => {
  const result = await runCore(baseArguments('http://127.0.0.1:1/api/deploys', ['--strict']), {
    env: { PATH: '/path-that-does-not-exist' },
  });

  assert.equal(result.code, 4);
  assert.match(result.stdout, /roko-adapter: curl is required/);
  assert.doesNotMatch(result.stdout + result.stderr, /test-secret-token/);
});
