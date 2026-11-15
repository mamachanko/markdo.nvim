# Contributing

Mark Do targets Neovim 0.11+ and uses the Markdown block parser for structure.
Keep default keys free and document user-visible behavior in both README.md
and `doc/markdo.txt`.

## Validation

From the repository root:

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/readme.lua
```

The first command includes the assertion-backed demo walkthrough. CI runs both
commands on Linux and macOS with Neovim 0.11.0 and current stable. Add regression
tests for behavior changes. Regenerate help tags after updating help:

```sh
nvim --headless -u NONE '+helptags doc' +qa
```

## Demo review for every feature

Every user-facing feature should include a decision about the README demo:

- Update [scripts/demo.lua](scripts/demo.lua) to demonstrate and assert the new
  behavior, then regenerate and visually review [docs/demo.gif](docs/demo.gif).
- If a demo change would not help users understand the feature, explain why in
  the PR. New commands excluded from the walkthrough need a specific reason in
  the scenario's `M.exceptions` table.

Keep the recording legible at phone width and make shell execution the final
chapter. Use real Neovim output. The recorder requires a working clipboard;
only the headless tests use a fixture provider. If the walkthrough becomes too
long, add a focused companion clip rather than speeding through unreadable
frames. See [recording instructions](docs/demo.md).

## Pull requests and releases

Use a Conventional Commit title, such as `feat: add a checklist action` or
`fix: preserve task boundaries`. Include validation and the demo decision.
Preserve the title and any breaking-change footer when squash merging;
[release maintenance](docs/releases.md) explains versioning and publication.
