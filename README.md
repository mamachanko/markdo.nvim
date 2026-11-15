# ☑️ Mark Do

Work through Markdown runbooks in Neovim: check nested tasks, copy code, and run shell fences in a floating terminal.

[![CI](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/mamachanko/markdo.nvim)](https://github.com/mamachanko/markdo.nvim/releases)

[Installation](#installation) · [Quick start](#quick-start) · [Commands](#commands) · [Behavior](#behavior) · [Help & development](#help-and-development)

![Neovim walkthrough: check health, navigate and complete tasks, inspect progress, reset, copy, then run an interactive shell fence](docs/demo.gif)

*Check dependencies, work through tasks and progress, reset the checklist, then copy and run its shell fence.*

[Demo chapters and recording instructions](docs/demo.md) · Uses the optional statusline example below.

Keep your runbooks as ordinary Markdown, with the checklist and its commands together:

- **Nested tasks** — move between unfinished tasks and complete them from text or code; parent checkboxes reflect progress below them.
- **Code in context** — copy a fence body or run a shell script directly from the task it belongs to.
- **Interactive execution** — inspect live output, enter terminal input, and keep the result visible after exit.

Mark Do reads the current buffer, including unsaved edits. It works without a setup call and leaves your keys free.

## Requirements

| Dependency | Used for |
| --- | --- |
| **Neovim 0.11+** | All commands; shell execution supports Linux and macOS |
| **Tree-sitter Markdown parser** (`markdown`) | Task scope, fence selection, and headings |
| **Clipboard provider** | Copy only; check `:checkhealth vim.provider` |
| **Shell executable** | Run only; `sh`, `bash`, `zsh`, `fish`, or Neovim's configured shell |

Official Neovim releases include the Markdown block parser. If your distribution omits it, install it with `:TSInstall markdown` using nvim-treesitter, or add a compatible `parser/markdown.so` to your runtimepath. Mark Do reports a missing parser.

For clipboard support, install a platform clipboard tool or configure `g:clipboard`; see `:help clipboard`.

Check your installation with **`:checkhealth markdo`**. It verifies Neovim and Markdown parsing, then reports clipboard and shell availability with suggested fixes. Missing core dependencies are errors; unavailable optional capabilities are warnings. With Lazy.nvim, open a Markdown buffer first or use `:Lazy load markdo.nvim` before running the check.

## Installation

### Lazy.nvim

Add this spec to your plugins. **No `setup()` call is needed.**

<!-- example:lazy -->
```lua
{
  'mamachanko/markdo.nvim',
  ft = 'markdown',
}
```

### Native Neovim packages

With Neovim's default Linux/macOS data directory:

<!-- example:native -->
```sh
pack_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start"
mkdir -p "$pack_dir"
git clone https://github.com/mamachanko/markdo.nvim.git "$pack_dir/markdo.nvim"
```

Restart Neovim, then run `:helptags ALL` to index the help file.

<details>
<summary>Custom data directory or NVIM_APPNAME</summary>

Use `:lua print(vim.fn.stdpath('data'))` to find your data directory. Install the plugin beneath it at `site/pack/plugins/start/markdo.nvim`.

</details>

### Optional keymaps

The following `init.lua` example keeps the actions under `<leader>x`, only in Markdown buffers. It works with either installation above.

<!-- example:keymaps -->
```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(ev)
    for key, action in pairs({
      ['<leader>xx'] = 'Toggle',
      ['<leader>xd'] = 'Done',
      ['<leader>xj'] = 'DoneNext',
      ['<leader>xr'] = 'Reset',
      ['<leader>xc'] = 'Copy',
      ['<leader>xe'] = 'Run',
      ['<leader>xn'] = 'Next',
      ['<leader>xp'] = 'Prev',
      ['<leader>xs'] = 'Progress',
      ['<leader>xv'] = 'ProgressToggle',
      -- ['<leader>x<Space>'] = 'Run', -- Alternative to <leader>xe.
    }) do
      vim.keymap.set('n', key, '<Plug>(MarkDo' .. action .. ')',
        { buffer = ev.buf, desc = 'Mark Do ' .. action })
    end
  end,
})
```

All letters are lowercase. To use `<leader>x<Space>` for Run, replace the `<leader>xe` entry with the commented entry above. `<Plug>` mappings resolve when the plugin loads.

## Quick start

Open [examples/runbook.md](examples/runbook.md), or save the following as `morning.md`:

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

1. **Copy.** Place the cursor on **Run the greeting** (line 4), or inside its fence. Use `:MarkDoCopy` to copy the three script lines to the clipboard.
2. **Complete and move.** Use `:MarkDoDoneNext` to check that child and move to **Review the output** (line 10). Use `:MarkDoDone` to finish the second child. The parent checks automatically:

<!-- example:completed -->
```markdown
- [x] Ready for the day
  - [x] Run the greeting
    …
  - [x] Review the output
```

3. **Inspect progress.** Use `:MarkDoProgress` for the summary and `:MarkDoProgressToggle` for inline parent counts. Toggle the child with `:MarkDoToggle` and the parent reopens; one undo restores both.
4. **Reset.** Put the cursor on the parent (line 3) and use `:MarkDoReset` to reopen it and both children in one undo step. Section and whole-buffer scopes are also available below.
5. **Execute.** Return to **Run the greeting** (line 4) and use `:MarkDoRun`. The float prints `Hello, Neovim!`, pauses one second, and shows `exit 0`. Press `Ctrl-\`, then `Ctrl-N` to leave terminal mode, then **q** to close the completed float. Running the script leaves the checklist open.

## Commands

| Command | Example key | Action |
| --- | --- | --- |
| `:MarkDoToggle` | `<leader>xx` | Reverse the current task |
| `:MarkDoDone` | `<leader>xd` | Check the current task; checked tasks stay checked |
| `:MarkDoDoneNext` | `<leader>xj` | Check the current task and move to the next unfinished task |
| `:MarkDoReset [scope]` | `<leader>xr` | Reopen the current task subtree, section, or buffer |
| `:MarkDoCopy` | `<leader>xc` | Copy the selected fence body to the `+` register |
| `:MarkDoRun` | `<leader>xe` | Run the selected shell fence in a float |
| `:MarkDoNext` | `<leader>xn` | Jump to the next unfinished task |
| `:MarkDoPrev` | `<leader>xp` | Jump to the previous unfinished task |
| `:MarkDoProgress` | `<leader>xs` | Show completion for the current buffer |
| `:MarkDoProgressToggle` | `<leader>xv` | Toggle inline progress beside parent tasks |

Example keys come from the [optional keymaps](#optional-keymaps) above. The plugin assigns none by default. Commands and mappings are buffer-local to Markdown, including buffers open before the plugin loads.

<details>
<summary>&lt;Plug&gt; mapping reference</summary>

Use these normal-mode mappings in your own key configuration:

| Mapping | Command |
| --- | --- |
| `<Plug>(MarkDoToggle)` | `:MarkDoToggle` |
| `<Plug>(MarkDoDone)` | `:MarkDoDone` |
| `<Plug>(MarkDoDoneNext)` | `:MarkDoDoneNext` |
| `<Plug>(MarkDoReset)` | `:MarkDoReset` |
| `<Plug>(MarkDoCopy)` | `:MarkDoCopy` |
| `<Plug>(MarkDoRun)` | `:MarkDoRun` |
| `<Plug>(MarkDoNext)` | `:MarkDoNext` |
| `<Plug>(MarkDoPrev)` | `:MarkDoPrev` |
| `<Plug>(MarkDoProgress)` | `:MarkDoProgress` |
| `<Plug>(MarkDoProgressToggle)` | `:MarkDoProgressToggle` |

</details>

## Behavior

### Tasks and parent completion

The innermost checkbox item containing the cursor is the current task. Its scope includes continuation paragraphs, nested plain lists, and fenced code. Ordered and unordered lists support `[ ]`, `[x]`, and `[X]`; checking writes `[x]`. Checkbox text inside code is treated as code. Blank separators between sibling items and positions outside tasks leave the buffer unchanged and report a short message.

After a checkbox changes, Mark Do recomputes its checkbox ancestors from the bottom up. A parent checks when **all descendant tasks are checked**, and reopens when any are open. Plain list items can contain tasks but have no checkbox state.

Editing a parent with Done or Toggle leaves its descendants alone; the next changed descendant recomputes the parent. Manual text edits do not trigger updates. Each command changes only checkbox characters, preserves the cursor, and forms **one undo step**, including parent changes.

### Complete and continue

`:MarkDoDoneNext` checks the current task using the same scope and ancestor rules as Done, then moves to the next unfinished task after the cursor's line. It reads the updated buffer, skips checked tasks and code, opens destination folds, and does not wrap. Checkbox changes, including parent updates, remain one undo step.

If the current task is already checked, it advances without changing any checkboxes or adding an undo step. If there is no following unfinished task, it keeps the completion, preserves the cursor, and reports a short message. Outside a task, it reports **No task at cursor** and leaves both text and cursor alone. The ordinary Done command continues to preserve the cursor.

### Resetting a checklist

Use Reset to prepare a runbook for another run. Choose the scope explicitly when going beyond the task at the cursor:

| Command | Scope |
| --- | --- |
| `:MarkDoReset` or `:MarkDoReset task` | Current checkbox task and all its checkbox descendants |
| `:MarkDoReset section` | Current heading section, including subheadings |
| `:MarkDoReset buffer` | All checkbox tasks in the current buffer |

The optional `<leader>xr` binding uses the default **task** scope. Place the cursor on the parent, its continuation text, or its code to reset that subtree. Blank sibling separators and positions outside a task report a message; they do not expand the scope.

A section ends at the next heading of the same or higher level and stays within its Markdown container. Both ATX (`# Heading`) and setext headings work. Before the first document heading, section scope covers only the preamble; without document headings, the preamble is the whole buffer. Put the cursor on a parent heading to include its subheadings.

Reset changes checked `[x]`/`[X]` markers to `[ ]`, preserves the cursor and all other text, and leaves checkbox text inside code alone. It also reopens checked ancestors of changed tasks outside the chosen scope. The entire operation is **one undo step**, including ancestor changes. If the selected tasks are already open, nothing changes, including ancestor states and undo history. Progress summaries refresh automatically.

### Completion progress

`:MarkDoProgress` reports completion for the whole current buffer, for example `Mark Do: 6/8 tasks complete (75%)`. The optional `<leader>xs` binding above shows this summary.

Progress counts **checkbox tasks with no checkbox descendants**. A parent with two children contributes its two children to the total. A standalone task counts once; plain list items and checkbox text inside code do not count. A manually checked parent with an open child still has incomplete progress.

The percentage rounds to the nearest whole number. An empty checklist reports **No tasks**. Progress reads unsaved edits and leaves the Markdown unchanged.

#### Inline parent progress

Use `:MarkDoProgressToggle` (optional `<leader>xv`) to show progress beside parent tasks in the current buffer:

```text
- [ ] Deploy                 1/3 · 33%
  - [x] Run tests
  - [ ] Build
  - [ ] Publish
```

The suffix is subtle virtual text, highlighted like comments; it is never written into the Markdown. Each parent shows the completed leaf tasks in its own subtree. Standalone tasks, plain items, and checkbox text inside fences receive no annotation.

Inline progress is **off by default** and toggles independently for each buffer. It refreshes after edits, completion commands, undo, and redo. Manual text edits update the numbers without changing checkbox states. Toggle again to hide it. Unloading the buffer or changing its filetype away from Markdown disables it.

<details>
<summary>Statusline integration and Lua API</summary>

`require('markdo').progress(bufnr)` returns `{ completed, total, percent }` for a Markdown buffer. Omit `bufnr` or pass `0` for the current buffer. With no tasks, `completed` and `total` are `0` and `percent` is `nil`. On an unavailable parser or an invalid, unloaded, or non-Markdown buffer, it returns `nil, error` without notifying. Results are cached until the buffer changes.

For Neovim's built-in statusline, add this optional example to `init.lua`:

<!-- example:statusline -->
```lua
function _G.markdo_progress()
  if vim.bo.filetype ~= 'markdown' then return '' end
  local progress = require('markdo').progress()
  if not progress or progress.total == 0 then return '' end
  return ('%d/%d (%d%%)'):format(
    progress.completed, progress.total, progress.percent)
end
vim.opt.statusline:append(' %{v:lua.markdo_progress()}')
```

The helper returns an empty string for buffers without a checklist. Mark Do does not modify your statusline by default.

</details>

### Navigating unfinished tasks

`:MarkDoNext` and `:MarkDoPrev` move to the checkbox of the next or previous unchecked task in the current buffer. They follow document order across headings, include unfinished parent and child tasks, and skip checked tasks and checkbox text inside fences. Closed folds at the destination open automatically.

Navigation searches strictly after or before the **cursor's line**, so repeating a command moves on from the task under the cursor. From continuation text or code, Prev can return to that task's checkbox. At either end, a short message appears and the cursor stays put; navigation does not wrap. Both commands read unsaved edits and leave the checklist unchanged.

### Fence selection

Copy and Run share the same selection rules:

| Cursor location | Selected fence |
| --- | --- |
| On or inside a fence, including either delimiter | That fence |
| In a task | A fence whose nearest checkbox ancestor is that task |
| Outside tasks and fences | The next fence outside any task, before the next heading |

If a task owns several fences, `vim.ui.select` shows each fence's language, opening line number, and first nonblank body line. Child-task fences belong to the child. Outside tasks, a heading of any level ends the search; before the first heading, only the preamble is searched.

Cancelling the picker does nothing. Editing or deleting the source while it is open cancels the action and asks you to retry. No match, an incomplete fence, or an empty body produces a short message. An unusable selection never falls through to another fence.

### Copying code

Backtick and tilde fences are supported, with any language label or none. Mark Do removes delimiters, the label, Markdown container prefixes, and fence indentation. **Script-relative indentation, blank lines, quotes, and comments are preserved.**

Copy writes characterwise text to `+` without adding a final newline; existing blank final body lines remain. A missing clipboard provider reports a message and leaves other registers alone.

### Running shell fences

The first word of the fence's info string selects the interpreter:

| Label | Invocation |
| --- | --- |
| `sh`, `bash`, `zsh`, `fish` | Named executable with the entire body as one `-c` argument |
| `shell` | Neovim's `shell` and `shellcmdflag` options |

Each Run starts a fresh asynchronous terminal job, inherits Neovim's environment, and uses the **originating window's effective working directory**, including `:lcd` and `:tcd`. Variables and `cd` persist across lines within that run. An unlabelled or unsupported fence, or a missing executable, reports an error.

Scripts run only when you explicitly invoke Run. Exit status never changes the checklist. Output stays visible after exit, with the code in the float title and `b:markdo_exit_code`.

The float opens in terminal mode for live input. One job may be active per Neovim instance; a second Run focuses it.

| Terminal keys | Action |
| --- | --- |
| `Ctrl-\`, then `Ctrl-N` | Enter terminal-buffer Normal mode |
| **x** in Normal mode | Stop the job and keep its output |
| **q** in Normal mode | Close the float after exit |

Closing the float another way stops an active job and cleans up its buffer. Background job management is deferred.

## Help and development

- **Reference:** `:help markdo`
- **Diagnostics:** `:checkhealth markdo` (see `:help markdo-health`)
- **Release notes:** [GitHub Releases](https://github.com/mamachanko/markdo.nvim/releases)
- **Release process:** [Version rules and squash-merge guidance](docs/releases.md)
- **Demo:** [Chapters and recording instructions](docs/demo.md) for the real Neovim UI capture above
- **Contributing:** [Development and demo review](CONTRIBUTING.md)

From the repository root, with Neovim and its Markdown parser:

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/readme.lua
```

CI tests Neovim **0.11.0** and **current stable** on Linux and macOS, including fork pull requests. Tests use real parsing, a fake clipboard provider, and harmless terminal jobs.

<details>
<summary>Check release tooling locally</summary>

With Node.js 24.10+:

```sh
npm ci
npm run test:release
```

These checks use throwaway Git histories. See [release maintenance](docs/releases.md) for the version policy and test cases.

</details>

## License

[MIT](LICENSE) © Max Brauer
