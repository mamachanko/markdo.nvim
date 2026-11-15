# README demo

[demo.gif](demo.gif) is a roughly **38-second recording of real Neovim 0.11.0**
at **40 columns × 18 rows**. It uses [examples/demo.md](../examples/demo.md), a
small interactive runbook with a separate Archive section to make reset scopes
visible. The README quick start uses the simpler [runbook.md](../examples/runbook.md).

## Walkthrough

| Chapter | What the recording shows |
| --- | --- |
| Health | `:checkhealth markdo`: Neovim, parser, clipboard, and shell diagnostics |
| Navigation | Next and Prev between unfinished tasks |
| Completion | Done and Next, Done, Toggle, automatic parent completion and reopening |
| Progress | Whole-buffer summary, optional statusline, and inline parent counts |
| Reset | Task subtree, section, and buffer scopes; undo; Archive preserved until buffer reset |
| Copy | Fence-body copy, then `:echo getreg('+')` to inspect the actual clipboard contents |
| Execute | **Last:** an interactive shell fence, typed input, live output, exit 0, and closing the float |

The Archive task starts checked. Whole-buffer progress counts three leaf tasks;
the Morning checks parent counts its own two children. The optional README
statusline integration is configured up front; inline annotations are enabled
explicitly with `:MarkDoProgressToggle`. Both remain optional plugin features.

The last chapter runs ordinary `sh` code that prompts for a name. Typing
`Neovim` produces `Hello, Neovim!`. The checklist stays open after the run.
Terminal input and closing with `Ctrl-\`, `Ctrl-N`, then `q` are part of this final
chapter; no checklist action follows execution.

## Reproduce the recording

Use Neovim 0.11+, its Markdown block parser, an installed `sh`, a working
Neovim clipboard provider, Python 3, and a monospace font. From the repository
root on Linux:

```sh
python3 -m venv /tmp/markdo-demo-venv
/tmp/markdo-demo-venv/bin/pip install pillow msgpack
/tmp/markdo-demo-venv/bin/python scripts/record-demo.py --nvim /path/to/nvim
```

Use `--font /path/to/monospace.ttf` if DejaVu Sans Mono is unavailable (for
example on macOS). `--output /tmp/demo.gif` writes a preview elsewhere;
`--stills /tmp/demo-frames` also saves each frame for visual review.

This recording used xclip with an isolated Xvfb display. A desktop clipboard
provider such as pbcopy or xclip works too. The recorder verifies the copied
body and characterwise register type, then restores the prior clipboard at
shutdown. It requires a real provider; it does not silently substitute a fake
one for recording.

The recorder attaches to an embedded Neovim using the public `ext_linegrid`
protocol and renders its actual redraw events, highlights, float, and cursor.
All commands are entered through Neovim input. Pauses become GIF frame
durations; the shell and terminal input run for real. The narrow viewport and
large font keep the clip legible when GitHub scales it to a phone.

It uses `-u NONE`, disables swap files, and never saves checklist edits to disk.
Demo dependencies are optional and are not plugin runtime dependencies.

## Verify behavior without recording

The recorder and headless tests share [scripts/demo.lua](../scripts/demo.lua).
The scenario asserts cursor destinations, checkbox roll-up, percentages,
subtree counts, reset boundaries, undo, clipboard bytes, terminal input/output,
exit status, and an unchanged file on disk. It also checks that every current
Mark Do command is demonstrated or has an explicit documented exception, and
that Run is the final command chapter.

```sh
nvim --headless -u NONE -l tests/demo.lua
```

This standalone test uses an isolated fixture clipboard provider. It is also
included in the standard `tests/run.lua` command, so CI replays the walkthrough
on minimum/stable Neovim on Linux and macOS without Python, fonts, or a display.

## Maintaining the demo

For each user-facing feature, review whether the README demo should change.
Extend the shared scenario and record the result when appropriate. If a new
command does not belong in the walkthrough, add its reason to `M.exceptions`
in `scripts/demo.lua` and explain that choice in the PR. Do not exclude a command
just to make the coverage check pass.

Keep execution as the last chapter. Review the GIF and its important frames at
phone width, update these chapters and README wording together, and follow the
[contribution guide](../CONTRIBUTING.md).
