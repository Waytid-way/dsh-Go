import { test } from 'node:test';
import assert from 'node:assert/strict';
import { manifestMismatch } from '../ohos/plugins/manifest.mjs';

const pkg = (bin, overrides = {}) => ({ name: 'yaml', version: '2.9.1', ...overrides,
  ...(bin === undefined ? {} : { bin }) });

test('npm string bin and normalized registry map refer to the same command', () => {
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }), pkg('./bin.mjs')), null);
  assert.equal(manifestMismatch(pkg('./bin.mjs'), pkg({ yaml: 'bin.mjs' })), null);
});

test('scoped command uses the package name without its scope', () => {
  assert.equal(manifestMismatch(pkg({ cli: 'dist/cli.js' }, { name: '@team/cli' }),
    pkg('./dist/cli.js', { name: '@team/cli' })), null);
});

test('multi-command maps ignore property order and a leading ./', () => {
  assert.equal(manifestMismatch(pkg({ beta: './dist/b.js', alpha: 'dist/a.js' }),
    pkg({ alpha: './dist/a.js', beta: 'dist/b.js' })), null);
});

test('two absent bins compare equally', () => {
  assert.equal(manifestMismatch(pkg(undefined), pkg(undefined)), null);
});

test('missing, extra, renamed, and changed commands are rejected', () => {
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }), pkg(undefined)), 'bin');
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }), pkg({ yaml: 'other.js' })), 'bin');
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }), pkg({ renamed: 'bin.mjs' })), 'bin');
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }), pkg({ yaml: 'bin.mjs', extra: 'other.js' })), 'bin');
});

test('a different or malformed bin target remains a mismatch', () => {
  assert.equal(manifestMismatch(pkg({ yaml: './bin.mjs' }), pkg({ yaml: 1 })), 'bin');
  assert.equal(manifestMismatch(pkg(['bin.mjs']), pkg({ yaml: 'bin.mjs' })), 'bin');
});

test('every non-bin manifest field remains strictly compared', () => {
  assert.equal(manifestMismatch(pkg({ yaml: 'bin.mjs' }, { dependencies: { x: '1' } }),
    pkg('./bin.mjs', { dependencies: { x: '2' } })), 'dependencies');
  assert.equal(manifestMismatch(pkg(undefined, { version: '2.9.1' }),
    pkg(undefined, { version: '2.9.2' })), 'version');
});
