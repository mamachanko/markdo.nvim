# ☑️ Mark Do

Work through Markdown runbooks in Neovim: check nested tasks, copy code, run shell fences in a floating terminal, and save their results.

[![CI](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/mamachanko/markdo.nvim/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/mamachanko/markdo.nvim)](https://github.com/mamachanko/markdo.nvim/releases)

[Installation](#installation) · [Quick start](#quick-start) · [Commands](#commands) · [Behavior](#behavior) · [Help & development](#help-and-development)

![Neovim walkthrough using visible leader-key chords: complete tasks, inspect progress, focus, reset, copy, then run and capture a shell fence](docs/demo.gif)

*Work through a runbook with visible key chords, then run its shell fence and capture the result. Space is the demo’s example leader; all mappings are optional.*

[Demo chapters and recording instructions](docs/demo.md) · Uses the optional statusline and copy-on-navigation examples below.

Keep your runbooks as ordinary Markdown, with the checklist and its commands together:

- **Nested tasks** — move between unfinished leaf tasks and complete them from text or code; parent checkboxes reflect progress below them.
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
      ['<leader>xj'] = 'Next',
      ['<leader>xk'] = 'Prev',
      ['<leader>xr'] = 'Reset',
      ['<leader>xf'] = 'FocusToggle',
      ['<leader>xc'] = 'Copy',
      ['<leader>xe'] = 'Run',
      ['<leader>xo'] = 'Capture',
      ['<leader>xn'] = 'Next', -- Optional alias for xj.
      ['<leader>xp'] = 'Prev', -- Optional alias for xk.
      ['<leader>xs'] = 'Progress',
      ['<leader>xv'] = 'ProgressToggle',
      -- ['<leader>x<Space>'] = 'Run', -- Alternative to <leader>xe.
    }) do
      vim.keymap.set('n', key, '<Plug>(MarkDo' .. action .. ')',
        { buffer = ev.buf, desc = 'Mark Do ' .. action })
    end
    -- Optional shortcuts for the other reset scopes.
    for key, scope in pairs({ ['<leader>x1'] = 'section', ['<leader>x2'] = 'buffer' }) do
      vim.keymap.set('n', key, function() vim.cmd('MarkDoReset ' .. scope) end,
        { buffer = ev.buf, desc = 'Mark Do reset ' .. scope })
    end
  end,
})
```

All letters are lowercase. To use `<leader>x<Space>` for Run, replace the `<leader>xe` entry with the commented entry above. `<Plug>` mappings resolve when the plugin loads.

### Optional navigation settings

No setup call is needed for the defaults: navigation visits unfinished **leaf tasks**, and it leaves your clipboard alone. A leaf task has no checkbox descendants; plain list children and code do not make it a parent.

To opt into copying the destination task's code after a successful Next or Prev, configure this once:

<!-- example:navigation -->
```lua
require('markdo').setup({
  navigation = {
    leaf_only = true,
    copy_on_jump = true,
  },
})
```

With Lazy.nvim, you can instead add `opts = { navigation = { copy_on_jump = true } }` to the installation spec. To include parent tasks in navigation, set `leaf_only = false`. Each setup call starts from the defaults and applies the supplied settings; `require('markdo').setup()` restores the defaults. These options affect Next and Prev; Done and Toggle stay stationary.

**Upgrading from 1.x:** Next and Prev now skip parent tasks by default. Set `navigation.leaf_only = false` to restore their previous destinations. In the suggested keymaps, `xj` now means Next, and `xk` means Prev; update your own configuration if you copied the old `xj = DoneNext` example. Mark Do does not rewrite local mappings. DoneNext remains available as a compatibility command below.

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

1. **Navigate and copy.** From the heading (line 1), use `:MarkDoNext` (optional `<leader>xj`) to reach **Run the greeting** (line 4), skipping the parent category. `<leader>xk` goes back to the previous unfinished leaf. Use `:MarkDoCopy` to copy the three script lines, or opt into copy-on-navigation above.
2. **Complete, then move.** Use `:MarkDoDone` (optional `<leader>xd`) to check that child and stay there. Use `:MarkDoNext` to move to **Review the output** (line 10), then `:MarkDoDone` to finish it. The parent checks automatically:

<!-- example:completed -->
```markdown
- [x] Ready for the day
  - [x] Run the greeting
    …
  - [x] Review the output
```

3. **Inspect progress.** Use `:MarkDoProgress` for the summary and `:MarkDoProgressToggle` for inline parent counts. Toggle the child with `:MarkDoToggle` and the parent reopens; one undo restores both.
4. **Focus.** Use `:MarkDoFocusToggle` to fold completed branches. Toggle it again to restore your previous folds and view before continuing.
5. **Reset.** Put the cursor on the parent (line 3) and use `:MarkDoReset` to reopen it and both children in one undo step. Section and whole-buffer scopes are also available below.
6. **Execute.** Return to **Run the greeting** (line 4) and use `:MarkDoRun`. The float prints `Hello, Neovim!`, pauses one second, and shows `exit 0`. Press `Ctrl-\`, then `Ctrl-N` to leave terminal mode, then **q** to close the completed float. Running the script leaves the checklist open.
7. **Capture.** Back in the runbook, use `:MarkDoCapture` (optional `<leader>xo`) to insert the output and exit status beneath the shell fence. One undo removes the capture.

## Commands

| Command | Example key | Action |
| --- | --- | --- |
| `:MarkDoToggle` | `<leader>xx` | Reverse the current task |
| `:MarkDoDone` | `<leader>xd` | Check the current task; checked tasks stay checked |
| `:MarkDoReset [scope]` | `<leader>xr` | Reopen the current task subtree, section, or buffer |
| `:MarkDoFocusToggle` | `<leader>xf` | Fold completed branches in the current window |
| `:MarkDoCopy` | `<leader>xc` | Copy the selected fence body to the `+` register |
| `:MarkDoRun` | `<leader>xe` | Run the selected shell fence in a float |
| `:MarkDoCapture` | `<leader>xo` | Insert the latest run’s output and exit status beneath its source fence |
| `:MarkDoNext` | `<leader>xj` / `<leader>xn` | Jump to the next unfinished leaf task |
| `:MarkDoPrev` | `<leader>xk` / `<leader>xp` | Jump to the previous unfinished leaf task |
| `:MarkDoProgress` | `<leader>xs` | Show completion for the current buffer |
| `:MarkDoProgressToggle` | `<leader>xv` | Toggle inline progress beside parent tasks |

Example keys come from the [optional keymaps](#optional-keymaps) above. The plugin assigns none by default. Commands and mappings are buffer-local to Markdown, including buffers open before the plugin loads. The combined `:MarkDoDoneNext` command is retained for [compatibility](#compatibility-donenext), with no suggested key.

<details>
<summary>&lt;Plug&gt; mapping reference</summary>

Use these normal-mode mappings in your own key configuration:

| Mapping | Command |
| --- | --- |
| `<Plug>(MarkDoToggle)` | `:MarkDoToggle` |
| `<Plug>(MarkDoDone)` | `:MarkDoDone` |
| `<Plug>(MarkDoDoneNext)` | `:MarkDoDoneNext` |
| `<Plug>(MarkDoReset)` | `:MarkDoReset` |
| `<Plug>(MarkDoFocusToggle)` | `:MarkDoFocusToggle` |
| `<Plug>(MarkDoCopy)` | `:MarkDoCopy` |
| `<Plug>(MarkDoRun)` | `:MarkDoRun` |
| `<Plug>(MarkDoCapture)` | `:MarkDoCapture` |
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

Next and Prev visit unfinished **leaf checkbox tasks** in document order, across headings. A task with any checkbox descendants is a parent, even if those descendants are checked. A task containing only plain list items or code is still a leaf. Checkbox-like code is ignored. Set `navigation.leaf_only = false` to include parent tasks.

Navigation searches strictly after or before the **cursor's line**, so repeating a command moves on from the task under the cursor. From continuation text or code, Prev can return to that leaf's checkbox. At either end, a short message appears and the cursor stays put; navigation does not wrap. Both commands read unsaved edits, open destination folds, and leave the checklist and undo history unchanged.

With **`navigation.copy_on_jump = true`**, a successful Next or Prev copies the destination task's sole complete, nonempty fence to `+` as characterwise text, without an added final newline. Any language is supported, using the same body extraction as Copy. Only fences whose nearest checkbox ancestor is that destination qualify. With no fence, multiple fences, or an empty/incomplete fence, the clipboard stays as it is; navigation never opens a picker or borrows another task's fence. A failed jump does not copy. Missing or failing clipboard providers report a short message after the jump, without changing other registers or cancelling movement.

Copy-on-navigation is **off by default**. Done and Toggle never move or copy. Explicit Copy remains available when you want to choose among several fences. Navigation never executes a script.

### Focus mode

`:MarkDoFocusToggle` (optional `<leader>xf`) folds completed task branches in the **current window**. A branch is complete only when its own checkbox and every checkbox descendant are checked. A manually checked parent with an open child stays visible; completed children within unfinished branches can still fold. Real headings remain visible, including headings inside tasks. Checkbox-like code never creates a task or a separate fold.

Focus is **off by default**. It refreshes after edits, completion commands, reset, undo, and redo, without changing Markdown or adding undo entries. New splits start with your original folds, and existing windows keep independent views.

Toggle it off to restore the prior fold settings, fold definitions, open/closed states, cursor, and scroll view. Saved fold positions follow edits. While Focus is active it manages the window's folds: you can use `zo` to peek, and the next edit recomputes the Focus folds. Folding changes made during Focus are temporary.

Switching windows keeps Focus active. Displaying another buffer in that window, changing filetype away from Markdown, or closing the window ends it. Normal files and Markdown scratch buffers are supported.

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

<details>
<summary>Fences inside collapsible sections</summary>

You can copy from a task whose fence is inside `<details>`. Indent the wrapper and its contents to belong to that task, and keep a blank line after `</summary>` and before `</details>` so the contents are Markdown. Use a longer outer fence when the Markdown body includes code fences of its own:

<!-- example:details -->
`````markdown
- [ ] Release notes
  - [ ] Create PR

    <details>
    <summary>Release notes prompt</summary>

    ````markdown
    # Mission

    Write the release notes.
    ```sh
    printf 'example'
    ```
    ````

    </details>
`````

Put the cursor on **Create PR**, anywhere inside the outer fence, or on its delimiters, then use `:MarkDoCopy`. The copied body includes the inner triple-backtick example. The parent **Release notes** does not borrow its child's fence. Run uses the same selection rules, with shell-labelled fences.

</details>

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

### Capturing results

After a run exits, return to its Markdown buffer and use **`:MarkDoCapture`** (optional `<leader>xo`). The latest run for that buffer is inserted beneath its source shell fence as a `text` fence, with the exit status first:

<!-- example:captured -->
````markdown
    ```text
    exit 0

    Hello, Neovim!
    ```
````

Capture is explicit and works after you close the terminal. It reads the combined stdout/stderr received through the terminal, including echoed input. Terminal colours and control sequences are removed; carriage returns and backspaces overwrite the current line. Blank lines, text indentation, and lines wider than the float are retained. This is a plain transcript for shell scripts, rather than a replay of full-screen applications. It excludes terminal padding and Neovim’s process-exit message.

The inserted block preserves Markdown list and blockquote nesting. Its delimiter grows if the output contains backticks. Capture keeps all checkboxes as they are, preserves your cursor’s position in the text, and makes one undo step. Repeating Capture does nothing while that capture remains; undoing or deleting it allows capturing again. A new run starts a new result and leaves earlier captures intact. To rerun directly, put the cursor inside the shell fence; from a task containing several fences, the usual picker applies.

Only the latest run per loaded source buffer is retained, until the next run or buffer unload. Capture tracks the source fence through unrelated edits. If the fence changes, disappears, or no longer parses in that location, it asks you to run it again. An active run, unmodifiable buffer, or unavailable parser reports a short message. Output over **1 MiB** is refused, without inserting a partial result. The buffer is never saved automatically.

### Compatibility: DoneNext

The recommended workflow keeps completion and navigation separate. For existing configurations, `:MarkDoDoneNext` keeps its original combined behavior: it checks the current task, including ancestor roll-up, then moves to the next unfinished task. It includes parent tasks, opens destination folds, does not wrap, and never automatically copies. The navigation settings above apply only to Next and Prev.

Checkbox changes remain one undo step. An already checked task advances without changing text or undo history. With no next task, completion remains and the cursor stays put. Outside a task, it reports **No task at cursor** and leaves text and cursor alone. Its command and `<Plug>` mapping remain available; it has no suggested key and is omitted from the demo.

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
