import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const [requestFile, expectedSha, expectedDeployId] = process.argv.slice(2);
if (!requestFile || !expectedSha || !expectedDeployId) {
  throw new Error('usage: node assert-live-request.mjs FILE SHA DEPLOY_ID');
}

const lines = (await readFile(requestFile, 'utf8')).trim().split('\n');
assert.equal(lines.length, 1);
const request = JSON.parse(lines[0]);
assert.equal(request.method, 'POST');
assert.equal(request.url, '/api/deploys');
assert.equal(request.authorization, 'Bearer live-test-token');
assert.equal(request.contentType, 'application/json');
assert.deepEqual(JSON.parse(request.body), {
  environment: 'ci',
  sha: expectedSha,
  deployId: expectedDeployId,
});
