# README demo

[demo.gif](demo.gif) is a roughly **37-second recording of real Neovim 0.11.0**
at **56 columns × 24 rows**. It uses [examples/demo.md](../examples/demo.md), a
small interactive runbook with a separate Archive section to make reset scopes
visible. The README quick start uses the simpler [runbook.md](../examples/runbook.md).

## Walkthrough

| Chapter | What the recording shows |
| --- | --- |
| Health | `:checkhealth markdo`: Neovim, parser, clipboard, and shell diagnostics |
| Navigation | `xj` / `xk` visit unfinished leaves, skip the parent category, and optionally copy the destination’s code |
| Completion | Done stays on the task; Next moves separately; Toggle, parent completion and reopening |
| Progress | Whole-buffer summary, optional statusline, and inline parent counts |
| Focus | Fold completed branches, keep headings visible, then restore the previous view |
| Reset | Task subtree, section, and buffer scopes; undo; Archive preserved until buffer reset |
| Copy | Fence-body copy, then inspect the actual clipboard contents |
| Execute and capture | **Last:** run an interactive shell fence, type input, inspect output and exit 0, close the float, then save results beneath the source fence |

The Archive task starts checked. Whole-buffer progress counts three leaf tasks;
the Morning checks parent counts its own two children. The optional README
statusline integration is configured up front; inline annotations are enabled
explicitly with `:MarkDoProgressToggle`. The recording also loads the README's
**opt-in copy-on-navigation** example: after the first `Space x j`, `Space x i`
shows the automatically copied script. Navigation with no fence leaves that
clipboard untouched. Runtime defaults leave the clipboard alone; no setup
call is needed unless you want to change those defaults.

The last chapter runs ordinary `sh` code that prompts for a name. Typing
`Neovim` produces `Hello, Neovim!`. The checklist stays open after the run.
Terminal input, closing with `Ctrl-\`, `Ctrl-N`, then `q`, and capturing with
`Space x o` are part of this final chapter; no checklist action follows execution.

## Keys and framing

The larger viewport shows the whole runbook and its captured result. The footer
shows the **actual keys sent to Neovim**, with a short description. It is a
presentation overlay below the unaltered UI grid, not another plugin or a
simulated command result. There are no typed Ex commands in the recording.

The recording sets **Space as its example leader** and loads the README's
optional Markdown mappings verbatim. The plugin still assigns no default keys;
you can choose any leader or bindings. In the clip:

| Keys | Action |
| --- | --- |
| `Space x j` / `Space x k` | Next / Prev unfinished leaf |
| `Space x d` / `Space x x` | Done / Toggle, without moving |
| `Space x v` / `Space x s` | Inline / summary progress |
| `Space x f` | Focus on/off |
| `Space x r` / `Space x 1` / `Space x 2` | Reset task / section / buffer |
| `u` | Undo |
| `Space x c` | Copy |
| `Space x e` / `Space x o` | Run / Capture |
| `Ctrl-\`, `Ctrl-N`, then `q` | Leave terminal mode, close after exit |

The README also suggests `Space x n` / `Space x p` as aliases. The compatibility
DoneNext command is deliberately omitted: the recommended flow keeps navigation
and completion separate. Its exclusion is explained in `M.exceptions` and its
original behavior remains covered by headless tests.

Two recording-only inspection shortcuts are defined in `scripts/demo.lua`:
`Space x h` opens `:checkhealth markdo`, and `Space x i` displays the clipboard.
They are helpers for the walkthrough, not plugin commands or default mappings.
The footer's `Neovim Enter` shows input typed into the actual terminal.

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
provider such as pbcopy or xclip works too. The recorder verifies automatically and explicitly copied
bodies and characterwise register type, then restores the prior clipboard at
shutdown. It requires a real provider; it does not silently substitute a fake
one for recording.

The recorder attaches to an embedded Neovim using the public `ext_linegrid`
protocol and renders its actual redraw events, highlights, float, and cursor.
All actions are entered through Neovim input using the mappings above. Pauses
become GIF frame durations; the shell and terminal input run for real. The wider
viewport provides context, while the readable monospace font and keycap footer
make the actions easy to follow at smaller widths.

It uses `-u NONE`, disables swap files, and never saves checklist edits to disk.
Demo dependencies are optional and are not plugin runtime dependencies.

## Verify behavior without recording

The recorder and headless tests share [scripts/demo.lua](../scripts/demo.lua).
The scenario asserts leaf destinations, stationary completion, opt-in clipboard
writes, checkbox roll-up, percentages,
subtree counts, reset boundaries, undo, clipboard bytes, terminal input/output,
exit status, captured text/container ownership, and an unchanged file on disk.
It also checks that every current Mark Do command is demonstrated or has an
explicit documented exception, and
that Run and Capture form the final chapter. Mark Do actions are exercised
through their real keymaps. Only the headless replay sends terminal answer text
directly to the PTY, since headless feedkeys leaves terminal-input mode when its
queue drains; the real UI recording types those keys normally.

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

Keep execution and result capture as the last chapter. Review the GIF and its
important frames at phone width, update these chapters and README wording together, and follow the
[contribution guide](../CONTRIBUTING.md).
