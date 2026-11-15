# ☑️ Mark Do

Work through Markdown runbooks in Neovim: check nested tasks, copy code, and run shell fences in a floating terminal.

[![CI](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/mamachanko/markdo.nvim)](https://github.com/mamachanko/markdo.nvim/releases)

![Real Neovim demo: run a greeting in a floating terminal, then finish both children to check their parent](docs/demo.gif)

*Recorded from Neovim at 40 columns. Run → live output → finish children → parent checks.*

## Requirements

- **Neovim 0.11+** on Linux or macOS for running shell fences.
- **Tree-sitter's Markdown block parser** (`markdown`). Official Neovim releases include it. If your distribution omits it, use `:TSInstall markdown` with nvim-treesitter or install a compatible `parser/markdown.so` on your runtimepath. Mark Do reports a missing parser; there is no regex fallback.
- **Clipboard provider** for Copy: check `:checkhealth vim.provider`. Install a platform clipboard tool or configure `g:clipboard` (see `:help clipboard`). Checking tasks and running scripts do not need a clipboard.
- **Shell executable** for Run: `sh`, `bash`, `zsh`, or `fish` on PATH. The label `shell` uses Neovim's `shell` and `shellcmdflag` options.

## Installation

Defaults work immediately: **no `setup()` call, no default keys**.

### Lazy.nvim

Add this spec to your Lazy.nvim plugins:

<!-- example:lazy -->
```lua
{
  'mamachanko/markdo.nvim',
  ft = 'markdown',
}
```

### Native Neovim packages

With Neovim's default Linux/macOS data directory, run:

<!-- example:native -->
```sh
pack_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start"
mkdir -p "$pack_dir"
git clone https://github.com/mamachanko/markdo.nvim.git "$pack_dir/markdo.nvim"
```

Restart Neovim. If you use `NVIM_APPNAME` or a custom data directory, put the plugin in `site/pack/plugins/start/markdo.nvim` beneath `:lua print(vim.fn.stdpath('data'))` instead. Run `:helptags ALL` once to index help after a native installation.

### Optional Markdown keys

Choose your own keys; this `init.lua` example applies only to Markdown. It works with either installation above. `<Plug>` mappings resolve when the plugin loads.

<!-- example:keymaps -->
```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(ev)
    for key, action in pairs({
      ['<leader>xx'] = 'Toggle',
      ['<leader>xd'] = 'Done',
      ['<leader>xc'] = 'Copy',
      ['<leader>xe'] = 'Run',
      -- ['<leader>x<Space>'] = 'Run', -- Alternative to <leader>xe.
    }) do
      vim.keymap.set('n', key, '<Plug>(MarkDo' .. action .. ')',
        { buffer = ev.buf, desc = 'Mark Do ' .. action })
    end
  end,
})
```

These use lowercase `x`, `d`, `c`, and `e`. `<leader>x<Space>` is a comfortable alternative for Run: replace the `<leader>xe` entry with the commented entry above if you prefer it.

## Quick start

Save this as `morning.md`, or open [examples/runbook.md](examples/runbook.md):

<!-- example:runbook -->
````markdown
# Morning checks

- [ ] Ready for the day
  - [ ] Run the greeting
    ```sh
    name=Neovim
    printf 'Hello, %s!\n' "$name"
    sleep 1
    ```
  - [ ] Review the output
````

1. Put the cursor on **Run the greeting** (line 4), or anywhere in its fence. Run `:MarkDoRun`. The float prints `Hello, Neovim!`, pauses one second, and shows `exit 0`. The checklist stays open.
2. Press **Ctrl-\**, then **Ctrl-N** to leave terminal mode; press **q** to close the completed float.
3. Back on **Run the greeting**, run `:MarkDoCopy` to copy just the three script lines to the system clipboard. Run `:MarkDoDone` to check that child. Its parent stays open.
4. Move to **Review the output** (line 10) and run `:MarkDoDone`. The last child and the parent now check together:

<!-- example:completed -->
```markdown
- [x] Ready for the day
  - [x] Run the greeting
    …
  - [x] Review the output
```

The parent owns no fences here: put the cursor on the greeting child to Copy or Run. Toggle either child with `:MarkDoToggle` and the parent reopens. One undo reverses the child change and its parent roll-up.

## Commands

All commands and normal-mode `<Plug>` mappings are buffer-local to Markdown, including buffers already open when the plugin loads.

| Command | `<Plug>` mapping | Action |
| --- | --- | --- |
| `:MarkDoDone` | `<Plug>(MarkDoDone)` | Check the current task; checked tasks stay checked |
| `:MarkDoToggle` | `<Plug>(MarkDoToggle)` | Reverse the current task |
| `:MarkDoCopy` | `<Plug>(MarkDoCopy)` | Copy the selected fence body to `+` |
| `:MarkDoRun` | `<Plug>(MarkDoRun)` | Run the selected shell fence in a float |

## Behavior

### Tasks and roll-up

The innermost checkbox item containing the cursor wins, including continuation paragraphs, nested plain lists, and fenced code. Ordered and unordered lists support `[ ]`, `[x]`, and `[X]`; checking writes `[x]`. Checkbox text inside code is never a task. Blank separators between sibling items and positions outside tasks report a short message and leave the buffer alone.

After a checkbox changes, Mark Do recomputes its checkbox ancestors from the bottom up. An ancestor checks only when all descendant tasks are checked, and reopens when any are open. Plain items can contain tasks but have no checkbox state. Directly editing a parent with Done or Toggle leaves its descendants alone; the next changed descendant recomputes that parent. Manual text edits never trigger roll-up. Each command changes only checkbox characters, preserves the cursor, and forms one undo step.

### Fence selection and Copy

Copy and Run use the current buffer, including unsaved edits, in this order:

1. **On or inside a fence**, including its opening or closing delimiter: select that fence.
2. **In a task**: consider only fences whose nearest checkbox ancestor is that task. Select a sole match; with several, `vim.ui.select` shows language, line number, and first nonblank body line. Child-task fences belong to the child.
3. **Elsewhere**: select the next fence outside any task, stopping at the next heading of any level. Before the first heading, search only the preamble.

Cancelling the picker does nothing. Changing or deleting the source while it is open cancels the action and asks you to retry. Zero matches, an incomplete fence, or an empty body produces a message. An unusable selected fence never causes a different fence to be selected.

Backticks and tildes work. Mark Do removes delimiters, the language label, Markdown container prefixes, and fence indentation. Script-relative indentation, blank lines, quotes, and comments remain. Copy accepts any language or no language, writes characterwise text to `+`, and adds no final newline. Existing blank final body lines are preserved. A missing clipboard provider reports a message and leaves other registers alone.

### Shell execution

The first word of the fence's info string chooses the interpreter: `sh`, `bash`, `zsh`, and `fish` use their named executable with the whole body as one `-c` argument. `shell` uses Neovim's `shell` and `shellcmdflag`. An unlabelled or unsupported fence, or a missing executable, reports an error.

Every Run starts a fresh asynchronous terminal job, inherits Neovim's environment, and uses the **originating window's effective working directory**, including `:lcd`/`:tcd`. Variables and `cd` persist across lines within that run. Review scripts before running them: only an explicit Run executes code. Exit status never edits a checkbox.

Output stays visible after exit; the float title shows the code, also available as `b:markdo_exit_code`. One job may be active per Neovim instance. A second Run focuses it. The float opens in terminal mode for live input.

| Terminal keys | Action |
| --- | --- |
| **Ctrl-\**, then **Ctrl-N** | Enter terminal-buffer Normal mode |
| **x** in Normal mode | Stop the job and keep its output |
| **q** in Normal mode | Close the float after the job exits |

Closing the float another way stops an active job and cleans up its buffer. Background job management is deferred.

## Help, tests, and releases

Read `:help markdo` for the reference and [GitHub Releases](https://github.com/mamachanko/markdo.nvim/releases) for generated release notes. See [release maintenance](docs/releases.md) for Conventional Commits, squash merges, and the first version policy.

From the repository root, with Neovim and its Markdown parser:

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/readme.lua
```

CI runs these on Linux and macOS with **0.11.0** and **current stable**, including fork pull requests. Tests use a fake clipboard provider, real parsing, and harmless terminal jobs. To check release rules locally with Node.js 24.10+:

```sh
npm ci
npm run test:release
```

The short demo is captured from a real Neovim UI; [recording instructions](docs/demo.md) describe how to reproduce it.
