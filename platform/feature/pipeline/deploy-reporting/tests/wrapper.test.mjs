import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const actionPath = path.join(testDirectory, '..', 'wrappers', 'github', 'action.yml');

test('GitHub wrapper passes the complete core contract', async () => {
  const action = await readFile(actionPath, 'utf8');

  assert.match(action, /roko-adapter\.sh/);
  assert.match(action, /roko-adapter\.ps1/);
  for (const argument of ['--url', '--token', '--environment', '--sha', '--deploy-id']) {
    assert.match(action, new RegExp(argument));
  }
  assert.match(action, /github\.sha/);
  assert.match(action, /GITHUB_RUN_ID.*GITHUB_RUN_ATTEMPT/);
  assert.doesNotMatch(action, /set -x/);
  assert.doesNotMatch(action, /Set-PSDebug/);
});

test('GitHub wrapper resolves both cores from its nested action directory', async () => {
  const action = await readFile(actionPath, 'utf8');

  assert.match(action, /GITHUB_ACTION_PATH\/\.\.\/\.\.\/core\/roko-adapter\.sh/);
  assert.match(action, /GITHUB_ACTION_PATH\/\.\.\/\.\.\/core\/roko-adapter\.ps1/);
});
