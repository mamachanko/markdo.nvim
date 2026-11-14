// Real semantic-release dry runs against disposable local Git remotes.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { Writable } from 'node:stream';
import semanticRelease from 'semantic-release';
import config from '../release.config.mjs';

const cases = [
  ['patch', 'fix: preserve blank lines', '1.2.4'],
  ['minor', 'feat: add a shell picker', '1.3.0'],
  ['major subject', 'feat!: change task selection', '2.0.0'],
  ['major footer', 'fix: change task selection\n\nBREAKING CHANGE: task scope now follows headings', '2.0.0'],
  ['docs only', 'docs: clarify installation', null],
  ['maintenance only', 'chore: refresh tooling', null],
  ['CI only', 'ci: update test matrix', null],
  ['first patch', 'fix: preserve blank lines', '1.0.0', false],
  ['first feature', 'feat: add a shell picker', '1.0.0', false],
  ['first breaking', 'feat!: change task selection', '1.0.0', false],
  ['untagged docs', 'docs: clarify installation', null, false],
];
for (const [name, subject, expected, tagged = true] of cases) {
  const root = mkdtempSync(join(tmpdir(), 'markdo-release-'));
  const cwd = join(root, 'work');
  const remote = join(root, 'origin.git');
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const env = { ...process.env };
  // A PR runner's GitHub environment must not select its real repository/ref.
  for (const key of Object.keys(env)) {
    if (/^(GITHUB_|GIT_|CI$|CONTINUOUS_INTEGRATION$|BUILD_NUMBER$|RUN_ID$)/.test(key)) delete env[key];
  }
  env.GIT_AUTHOR_NAME = env.GIT_COMMITTER_NAME = 'Mark Do test';
  env.GIT_AUTHOR_EMAIL = env.GIT_COMMITTER_EMAIL = 'test@example.invalid';
  let log = '';
  const output = new Writable({ write(chunk, _, done) { log += chunk.toString(); done(); } });
  try {
    execFileSync('git', ['init', '--bare', '--initial-branch=main', remote], { stdio: 'ignore' });
    execFileSync('git', ['init', '--initial-branch=main', cwd], { stdio: 'ignore' });
    git('config', 'user.name', 'Mark Do test'); git('config', 'user.email', 'test@example.invalid');
    git('config', 'commit.gpgsign', 'false'); git('config', 'tag.gpgsign', 'false');
    git('commit', '--allow-empty', '-m', 'chore: initial history');
    if (tagged) git('tag', 'v1.2.3');
    git('commit', '--allow-empty', '-m', subject);
    git('remote', 'add', 'origin', remote);
    git('push', '--tags', 'origin', 'main');
    const before = git('rev-parse', 'HEAD');
    const result = await semanticRelease({
      ...config,
      repositoryUrl: pathToFileURL(remote).href,
      dryRun: true,
      ci: false,
      // Exercise production analyzer/notes settings without GitHub credentials.
      plugins: config.plugins.filter(([plugin]) => plugin !== '@semantic-release/github'),
    }, { cwd, env, stdout: output, stderr: output });
    assert.equal(result ? result.nextRelease.version : null, expected, log);
    if (result) {
      assert.equal(result.nextRelease.gitTag, `v${expected}`);
      assert.match(result.nextRelease.notes, /preserve blank lines|shell picker|task selection/);
    }
    assert.equal(git('rev-parse', 'HEAD'), before, 'dry run must not commit');
    assert.equal(git('tag'), tagged ? 'v1.2.3' : '', 'dry run must not tag');
    console.log(`PASS ${name}: ${expected ?? 'no release'}`);
  } catch (error) {
    console.error(log);
    throw error;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
console.log(`${cases.length} release-history cases passed`);
