# Mark Do

Work through Markdown runbooks and checklists in Neovim 0.11+. Check tasks,
copy code, and explicitly run shell fences in an interactive floating terminal.
No setup call or default keys.

## Install

With [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'mamachango/markdo.nvim',
  ft = 'markdown',
  init = function()
    -- Choose your own Markdown keys. These are examples, not defaults.
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'markdown',
      callback = function(ev)
        for key, action in pairs({
          ['<leader>md'] = 'Done', ['<leader>mt'] = 'Toggle',
          ['<leader>mc'] = 'Copy', ['<leader>mr'] = 'Run',
        }) do
          vim.keymap.set('n', key, '<Plug>(MarkDo' .. action .. ')',
            { buffer = ev.buf, desc = 'Mark Do ' .. action })
        end
      end,
    })
  end,
}
```

Requires the Tree-sitter **Markdown block parser** (`markdown`). Official
Neovim 0.11 distributions include it. If your distribution omits it, install
with `:TSInstall markdown` using nvim-treesitter, or put a compatible compiled
`parser/markdown.so` (platform equivalent) on your runtimepath. No regex fallback
is used. Copy requires a working Neovim clipboard provider (`:checkhealth
vim.provider`); configure `g:clipboard` or install an appropriate clipboard tool.
Run supports macOS and Linux and needs the selected interpreter on PATH.

## Commands

Commands and normal-mode `<Plug>` mappings are buffer-local to Markdown,
including Markdown buffers already loaded when the plugin loads.

| Command | Mapping | Action |
| --- | --- | --- |
| `:MarkDoDone` | `<Plug>(MarkDoDone)` | Check the current task; checked tasks are unchanged |
| `:MarkDoToggle` | `<Plug>(MarkDoToggle)` | Reverse the current task |
| `:MarkDoCopy` | `<Plug>(MarkDoCopy)` | Copy the chosen fence body to `+` |
| `:MarkDoRun` | `<Plug>(MarkDoRun)` | Run the chosen shell fence in a float |

The innermost checkbox list item containing the cursor wins, including from
continuation paragraphs, nested plain lists, and code. Ordered and unordered
lists support `[ ]`, `[x]`, and `[X]`; checking writes `[x]`. Code is never parsed
as tasks. Blank separators between sibling items and positions outside tasks do
nothing except report a short message.

A changed checkbox recomputes its checkbox ancestors bottom up: an ancestor
checks only when all descendant tasks are checked and reopens if any are open.
Plain list items participate in ancestry without a state. Editing a parent with
a command leaves descendants alone. The next changed descendant recomputes that
parent. Manual text edits do not trigger roll-up. Each command changes only
checkbox characters, preserves the cursor, and is one undo step.

## Choosing a fence

Copy and Run read the current buffer, including unsaved edits:

1. On a fence's opening/closing delimiter or inside it, use that fence.
2. Inside a task, consider only fences whose nearest checkbox ancestor is that
   task. One is selected immediately; several use `vim.ui.select`, displaying
   language, opening line number, and first nonblank body line. A child's fence
   does not belong to its parent.
3. Elsewhere, use the next fence outside any task, stopping at the next heading
   of any level. Before the first heading, search only the preamble.

Cancelling a picker does nothing. Changing or deleting its source while it is
open cancels the operation with a retry message. An empty or incomplete chosen
fence reports a message; selection never falls through to another fence.

Backticks and tildes are supported. Container prefixes and fence indentation
are removed according to the Markdown parse; script indentation, blank lines,
quotes and comments remain. Copy accepts any language or no language. It writes
characterwise text to `+`, adds no final newline, and leaves other registers
alone. A blank final body line is preserved as an existing newline.

## Running

The first word of the info string must be `sh`, `bash`, `zsh`, `fish`, or `shell`.
Named languages use that executable with the entire body as one `-c` argument.
`shell` uses Neovim's `shell` and `shellcmdflag` options. Unlabelled, unsupported,
empty, incomplete, or unavailable interpreters report a message.

Every run starts a fresh asynchronous terminal job, inherits Neovim's
environment, and uses the originating window's effective working directory.
Variables and `cd` persist between lines within that run. Output remains visible
after exit, with the exit code in the float title and terminal buffer variable
`b:markdo_exit_code`. Exit status never changes a checkbox. Run executes only
when explicitly invoked; review scripts before running them.

One job may be active per Neovim instance; a second Run focuses it. The float
starts in terminal mode, allowing input. Use `<C-\\><C-n>` for terminal-buffer
normal mode, then `x` to stop and retain output, or `q` to close after exit.
Closing the window by another route stops its active job and cleans up its
buffer. Background job management is outside the first release.

See `:help markdo` for the help reference.

## Tests

From the repository root, with Neovim 0.11+ and its Markdown parser:

```sh
nvim --headless -u NONE -l tests/run.lua
```

No plugin manager or test framework is required. The tests use a fake clipboard
provider, real Tree-sitter parsing, and harmless shell terminal jobs. Structural
fixtures and the suite have been verified against official Neovim **0.11.0**'s
bundled Markdown parser. Tests cover task scope, roll-up/reopening, undo,
selection boundaries, picker cancellation/staleness, body preservation, and
terminal output, status, and cleanup.
