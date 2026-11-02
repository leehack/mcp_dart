import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readdir } from 'node:fs';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative, sep } from 'node:path';
import { setImmediate } from 'node:timers/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { Glob, glob, globSync } from 'glob';
import type { FSOption } from 'glob';
import { Minimatch, minimatch } from 'minimatch';

const fixtureRoot = fileURLToPath(new URL('../', import.meta.url));

test('glob and minimatch retain file selection and exclusion semantics', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'mcp-glob-compat-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'nested'));
  await mkdir(join(root, 'excluded'));
  for (const path of [
    'keep.txt',
    '.hidden.txt',
    'nested/child.txt',
    'excluded/no.txt',
  ]) {
    await writeFile(join(root, path), 'fixture');
  }
  const options = {
    cwd: root,
    dot: true,
    nodir: true,
    ignore: ['excluded/**'],
  };
  const expected = ['.hidden.txt', 'keep.txt', 'nested/child.txt'];
  const normalized = (paths: string[]): string[] =>
    paths.map((path) => path.split(sep).join('/')).sort();
  assert.deepEqual(normalized(await glob('**/*.txt', options)), expected);
  assert.deepEqual(normalized(globSync('**/*.txt', options)), expected);
  assert.deepEqual(
    normalized(await new Glob('**/*.txt', options).walk()),
    expected
  );
  assert.equal(minimatch('nested/child.txt', '**/*.txt', { dot: true }), true);
  assert.equal(minimatch('.hidden.txt', '**/*.txt', { dot: true }), true);
  assert.equal(minimatch('.hidden.txt', '**/*.txt'), false);
  assert.equal(minimatch('nested/child.md', '**/*.txt', { dot: true }), false);
  const matcher = new Minimatch('nested/**/*.txt', { dot: true });
  assert.equal(matcher.match('nested/child.txt'), true);
  assert.equal(matcher.match('excluded/child.txt'), false);
});

test(
  'glob abort stops traversal after the first directory read',
  { timeout: 5000 },
  async (t) => {
    const root = await mkdtemp(join(tmpdir(), 'mcp-glob-abort-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    await mkdir(join(root, 'nested'));
    await writeFile(join(root, 'nested', 'file.txt'), 'fixture');
    const controller = new AbortController();
    const reason = new Error('dependency compatibility abort');
    let reads = 0;
    const fs: FSOption = {
      readdir(path, options, callback) {
        reads += 1;
        if (controller.signal.aborted) {
          // Count forbidden work, but never perform filesystem I/O after abort.
          queueMicrotask(() => callback(null, []));
          return;
        }
        readdir(path, options, (error, entries) => {
          controller.abort(reason);
          callback(error, entries);
        });
      },
    };
    await assert.rejects(
      glob('**/*.txt', { cwd: root, fs, signal: controller.signal }),
      (error: unknown) => error === reason
    );
    await setImmediate();
    assert.equal(
      reads,
      1,
      'an aborted walk must not request child directories'
    );
  }
);

test(
  'minimatch bounds optimization-level-2 pattern amplification',
  { timeout: 10000 },
  () => {
    // A separate process provides a hard limit even if synchronous preprocessing
    // regresses. Eight transforms are enough to detect missing bounds safely.
    const probe = spawnSync(
      process.execPath,
      [
        '--input-type=module',
        '--eval',
        `import { Minimatch } from 'minimatch';
const matcher = new Minimatch('**/../a/b/'.repeat(8) + 'target.txt', {
  optimizationLevel: 2, braceExpandMax: 16,
});
console.log(JSON.stringify({ parts: matcher.globParts.length }));`,
      ],
      { cwd: fixtureRoot, encoding: 'utf8', timeout: 5000, maxBuffer: 16384 }
    );
    assert.ifError(probe.error);
    assert.equal(probe.status, 0, probe.stderr);
    const result = JSON.parse(probe.stdout) as { parts: number };
    assert.equal(Number.isInteger(result.parts), true);
    assert.ok(
      result.parts > 0 && result.parts <= 16,
      `expanded ${result.parts} patterns`
    );
  }
);

test(
  'ESLint selects TypeScript files and preserves ignored paths',
  { timeout: 30000 },
  async (t) => {
    const sourceRoot = await mkdtemp(
      join(fixtureRoot, 'src', 'dependency-compat-')
    );
    const ignoredRoot = await mkdtemp(
      join(fixtureRoot, 'dist', '.dependency-compat-')
    );
    t.after(async () => {
      await rm(sourceRoot, { recursive: true, force: true });
      await rm(ignoredRoot, { recursive: true, force: true });
    });
    const positive = join(sourceRoot, 'positive.ts');
    const negative = join(sourceRoot, 'negative.ts');
    const ignored = join(ignoredRoot, 'ignored.ts');
    await writeFile(positive, 'export const compatibilityValue: number = 1;\n');
    await writeFile(
      negative,
      'export function compare(value: number): boolean {\n  return value == 1;\n}\n'
    );
    await writeFile(ignored, 'export const ignored = ;\n');
    const result = spawnSync(
      process.execPath,
      [
        join(fixtureRoot, 'node_modules', 'eslint', 'bin', 'eslint.js'),
        '--format=json',
        '--no-warn-ignored',
        '--no-error-on-unmatched-pattern',
        `${relative(fixtureRoot, sourceRoot).split(sep).join('/')}/**/*.ts`,
        `${relative(fixtureRoot, ignoredRoot).split(sep).join('/')}/**/*.ts`,
      ],
      { cwd: fixtureRoot, encoding: 'utf8', timeout: 20000, maxBuffer: 65536 }
    );
    assert.ifError(result.error);
    assert.equal(result.status, 1, result.stderr);
    const reports = JSON.parse(result.stdout) as Array<{
      filePath: string;
      messages: Array<{ ruleId: string | null }>;
    }>;
    assert.deepEqual(
      reports.map((report) => report.filePath).sort(),
      [negative, positive].sort()
    );
    assert.deepEqual(
      reports.find((report) => report.filePath === positive)?.messages,
      []
    );
    assert.ok(
      reports
        .find((report) => report.filePath === negative)
        ?.messages.some((message) => message.ruleId === 'eqeqeq'),
      'the selected negative control must fail the checked-in equality rule'
    );
  }
);
