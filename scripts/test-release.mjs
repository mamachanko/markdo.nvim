// Real semantic-release dry runs against disposable local Git remotes.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Writable } from 'node:stream';
import semanticRelease from 'semantic-release';
import config from '../release.config.mjs';

const source = fileURLToPath(new URL('..', import.meta.url));
// Pin the historical fixture so future feature commits cannot mask a broken rule.
const bootstrapCommit = '945e04ba556427ae90b797d5443035718f21469d';

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
  ['same subject, different commit', 'Implement Markdown task actions, fence copy, and terminal runner', null, false],
  ['actual implementation bootstrap', null, '1.0.0', false],
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
    if (subject === null) {
      execFileSync('git', ['clone', '--no-hardlinks', '--no-tags', source, cwd], { stdio: 'ignore' });
      git('checkout', '-B', 'main', bootstrapCommit);
      git('remote', 'remove', 'origin');
    } else {
      execFileSync('git', ['init', '--initial-branch=main', cwd], { stdio: 'ignore' });
    }
    git('config', 'user.name', 'Mark Do test'); git('config', 'user.email', 'test@example.invalid');
    git('config', 'commit.gpgsign', 'false'); git('config', 'tag.gpgsign', 'false');
    if (subject !== null) git('commit', '--allow-empty', '-m', 'chore: initial history');
    if (tagged) git('tag', 'v1.2.3');
    if (subject !== null) git('commit', '--allow-empty', '-m', subject);
    git('remote', 'add', 'origin', remote);
    git('push', '--tags', 'origin', 'main');
    const before = git('rev-parse', 'HEAD');
    const releaseOptions = {
      ...config,
      repositoryUrl: pathToFileURL(remote).href,
      dryRun: true,
      ci: false,
      // Exercise production analyzer/notes settings without GitHub credentials.
      plugins: config.plugins.filter(([plugin]) => plugin !== '@semantic-release/github'),
    };
    const context = { cwd, env, stdout: output, stderr: output };
    const result = await semanticRelease(releaseOptions, context);
    assert.equal(result ? result.nextRelease.version : null, expected, log);
    if (result) {
      assert.equal(result.nextRelease.gitTag, `v${expected}`);
      assert.match(result.nextRelease.notes, /preserve blank lines|shell picker|task selection|Markdown task actions/);
    }
    assert.equal(git('rev-parse', 'HEAD'), before, 'dry run must not commit');
    assert.equal(git('tag'), tagged ? 'v1.2.3' : '', 'dry run must not tag');
    console.log(`PASS ${name}: ${expected ?? 'no release'}`);
    if (subject === null) {
      assert.match(result.nextRelease.notes, /Features/);
      assert.match(result.nextRelease.notes, /945e04b/);
      git('tag', 'v1.0.0');
      git('commit', '--allow-empty', '-m', 'docs: update the runbook');
      git('push', '--tags', 'origin', 'main');
      const afterBootstrap = await semanticRelease(releaseOptions, context);
      assert.equal(afterBootstrap, false, 'legacy rule must not release again after v1.0.0');
      console.log('PASS docs after bootstrap: no release');
    }
  } catch (error) {
    console.error(log);
    throw error;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
console.log(`${cases.length} release-history cases plus post-bootstrap check passed`);
