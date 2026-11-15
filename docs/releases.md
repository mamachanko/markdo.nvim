# Releases

The [release workflow](../.github/workflows/release.yml) runs on every push to
`main`. It calls the same reusable [CI workflow](../.github/workflows/ci.yml)
used by pull requests, testing Neovim 0.11.0 and current stable on Linux and
macOS, README examples, and release rules. Publishing depends on the entire
called workflow succeeding for that push's commit; it checks out that exact
SHA with full history and tags. Publication is serialized without cancelling
an in-progress release. If an older queued commit is behind main,
semantic-release skips it rather than publishing untested newer code.

CI uses `pull_request`, never `pull_request_target`: fork PRs run with read-only
permissions and need no secrets. Only the publishing job grants `contents:
write` to the built-in `GITHUB_TOKEN`; other permissions remain disabled. The
GitHub publisher creates tags and Releases only. Comments, failure issues,
labels, and linking releases into issues/PRs are disabled. There is no npm
publisher, changelog commit, or release commit. `npm ci` uses the committed
lockfile. Node dependencies are release tooling only; the plugin is pure Lua.

## Version rules

[semantic-release](https://github.com/semantic-release/semantic-release) uses
its Conventional Commits preset (both analyzer and notes generator):

| Commits since the latest release | Next version from v1.2.3 |
| --- | --- |
| `fix: preserve fence whitespace` | v1.2.4 |
| `feat: add a shell picker` | v1.3.0 |
| `feat!: change task scope` | v2.0.0 |
| Any type with a `BREAKING CHANGE:` footer | v2.0.0 |
| Only `docs:`, `chore:`, `ci:`, `build:`, `test:`, `style:`, or `refactor:` | No release |

`perf:` uses the preset's patch rule. A breaking marker/footer takes precedence
even on a maintenance commit; the largest bump wins across multiple commits.
Tags use **vMAJOR.MINOR.PATCH**. The GitHub Release contains generated notes.

**Untagged repository policy: the first releasable commit produces v1.0.0**,
even if that commit is a fix or breaking change. This is semantic-release's
standard initial-release policy, not a claim that a v0 version already exists.
Docs/maintenance-only history still skips release. From then on the table
applies relative to the latest release tag. Do not create a placeholder v0 tag.

## Initial implementation bootstrap

The original implementation commit (`945e04b`) was merged before Conventional
Commit subjects were used. The release configuration recognizes that exact
commit hash as a feature and includes it under Features in the generated notes.
This lets the existing history produce v1.0.0 without rewriting commits or
adding a placeholder tag. Once v1.0.0 is tagged, that commit is outside the
analyzed range and the exception has no further effect. Future nonconventional
subjects still do not trigger releases.

## Squash merging without losing release intent

semantic-release reads commits on `main`, so a PR's individual commit messages
will disappear when it is squash merged. Use a Conventional Commit **PR title**
and preserve that title as the **squash commit subject**. Check the final message
in GitHub's squash-merge dialog; do not rely on the default generated text.

A feature example:

```text
feat: add Markdown runbook actions
```

For a breaking change, preserve `!` in the subject and keep its explanation in
a real footer in the squash commit body, separated by a blank line:

```text
feat!: change task ownership

Tasks now follow the nearest checkbox ancestor.

BREAKING CHANGE: parent tasks no longer select their children's fences.
```

The footer must be in the resulting Git commit, not just a PR discussion or
review comment. A body-only `BREAKING CHANGE:` footer is sufficient even without
`!`. Do not squash a feature as `docs:` or `chore:` unless no release is intended.
Check the resulting main-branch subject after merging, especially when using
rebase or merge commits instead of squash.

## Local verification

With Node.js 24.10+:

```sh
npm ci
npm run test:release
```

The test creates disposable bare Git remotes and main branches, adds real
commits and optional v1.2.3 tags, and runs semantic-release in dry-run mode with
the production analyzer and notes-generator configuration. Only the GitHub
publisher is omitted; no GitHub token or live release is involved. It verifies
patch, minor, major (`!` and footer), no-release, and initial v1.0.0 behavior,
checks generated notes/tag names, and confirms dry runs neither tag nor commit.
It also clones the real repository history to verify the legacy bootstrap and
that subsequent docs-only history does not release again. CI fetches full
history for this regression check.
