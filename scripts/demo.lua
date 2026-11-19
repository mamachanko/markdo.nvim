-- Shared, assertion-backed walkthrough for the real UI recorder and headless CI.
local M = {}
local api = vim.api
local state = {}
local body = [[printf 'Your name: '
read name
printf 'Hello, %s!\n' "$name"
sleep 1]]
-- New commands must be covered below or have an explicit reviewed exception.
M.exceptions = {
  MarkDoDoneNext = 'Compatibility command combines completion and movement; the recommended workflow uses Done and independent Next/Prev.',
}
-- Space is this recording's example leader, not a plugin default.
M.width, M.height = 56, 24
M.steps = {
  { id = 'health', command = 'checkhealth markdo', keys = ' xh', label = 'Check dependencies', hold = 1500 },
  { id = 'next', command = 'MarkDoNext', keys = ' xj', label = 'Next leaf · opt-in copy', hold = 1400 },
  { id = 'auto_clipboard', keys = ' xi', label = 'Inspect automatically copied code', hold = 1400, message = true },
  { id = 'next_again', command = 'MarkDoNext', keys = ' xj', label = 'Next unfinished leaf', hold = 1100 },
  { id = 'prev', command = 'MarkDoPrev', keys = ' xk', label = 'Previous unfinished leaf', hold = 1100 },
  { id = 'done_first', command = 'MarkDoDone', keys = ' xd', label = 'Mark done · stay here', hold = 1300 },
  { id = 'next_after_done', command = 'MarkDoNext', keys = ' xj', label = 'Move independently', hold = 1100 },
  { id = 'inline', command = 'MarkDoProgressToggle', keys = ' xv', label = 'Show parent progress', hold = 1500 },
  { id = 'progress', command = 'MarkDoProgress', keys = ' xs', label = 'Checklist progress', hold = 1600 },
  { id = 'done', command = 'MarkDoDone', keys = ' xd', label = 'Complete the last child', hold = 1500 },
  { id = 'focus_on', command = 'MarkDoFocusToggle', keys = ' xf', label = 'Focus on unfinished work', hold = 1500 },
  { id = 'focus_off', command = 'MarkDoFocusToggle', keys = ' xf', label = 'Restore the previous view', hold = 1200 },
  { id = 'toggle', command = 'MarkDoToggle', keys = ' xx', label = 'Reopen a task', hold = 1400 },
  { id = 'reset_task', command = 'MarkDoReset', keys = ' xr', label = 'Reset this task', hold = 1300 },
  { id = 'undo_task', keys = 'u', label = 'Undo', hold = 800 },
  { id = 'reset_section', command = 'MarkDoReset section', keys = ' x1', label = 'Reset this section', hold = 1300 },
  { id = 'undo_section', keys = 'u', label = 'Undo', hold = 800 },
  { id = 'reset_buffer', command = 'MarkDoReset buffer', keys = ' x2', label = 'Reset this runbook', hold = 1500 },
  { id = 'copy', command = 'MarkDoCopy', keys = ' xc', label = 'Copy the shell fence', hold = 800 },
  { id = 'clipboard', keys = ' xi', label = 'Inspect the clipboard', hold = 1800, message = true },
  { id = 'run', command = 'MarkDoRun', keys = ' xe', label = 'Run the shell fence', hold = 1500 },
  { id = 'input', keys = 'Neovim<CR>', label = 'Answer the script', hold = 700 },
  { id = 'exit', keys = '', label = 'Finished · exit 0', hold = 1800 },
  { id = 'normal', keys = '<C-\\><C-n>', label = 'Leave terminal mode', hold = 600 },
  { id = 'close', keys = 'q', label = 'Close the completed terminal', hold = 600 },
  { id = 'capture', command = 'MarkDoCapture', keys = ' xo', label = 'Save the run in the runbook', hold = 2800 },
}

function M.setup(opts)
  opts = opts or {}
  vim.opt.rtp:prepend(vim.fn.getcwd())
  vim.g.mapleader = ' '
  local readme = table.concat(vim.fn.readfile('README.md'), '\n')
  local snippet = assert(readme:match('<!%-%- example:keymaps %-%->\n```lua\n(.-)\n```'))
  assert(loadstring(snippet))()
  vim.opt.termguicolors = true
  vim.opt.swapfile = false
  vim.opt.laststatus = 2
  vim.opt.showtabline = 0
  vim.opt.statusline = ' %t %= Mark Do '
  vim.opt.shortmess:append('IF')
  vim.cmd.colorscheme('habamax')
  vim.cmd('syntax on')
  if opts.fixture_clipboard then
    local register = { { 'previous test clipboard' }, 'v' }
    vim.g.clipboard = { name = 'demo test fixture', cache_enabled = 0,
      copy = { ['+'] = function(lines, kind) register = { vim.deepcopy(lines), kind } end, ['*'] = function() end },
      paste = { ['+'] = function() return vim.deepcopy(register) end, ['*'] = function() return { { '' }, 'v' } end } }
  end
  assert(vim.fn.has('clipboard') == 1, 'Recording requires a real clipboard provider; see :checkhealth markdo')
  state.clipboard = { value = vim.fn.getreg('+'), kind = vim.fn.getregtype('+') }
  vim.cmd('edit examples/demo.md')
  vim.bo.filetype = 'markdown'
  vim.cmd('runtime plugin/markdo.lua')
  -- Explicitly opt into the README example. Runtime defaults leave + alone.
  local navigation = assert(readme:match('<!%-%- example:navigation %-%->\n```lua\n(.-)\n```'))
  assert(loadstring(navigation))()
  state.buf, state.win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  state.original = vim.fn.readfile('examples/demo.md')
  assert(#state.original == 14, 'Update demo row assertions when changing its fixture')
  api.nvim_win_set_cursor(0, { 1, 0 })
  -- Optional README statusline integration, configured before the walkthrough.
  _G.markdo_demo_progress = function()
    if vim.bo.filetype ~= 'markdown' then return '' end
    local p = require('markdo').progress()
    return p and p.percent and ('%d/%d (%d%%)'):format(p.completed, p.total, p.percent) or ''
  end
  vim.opt.statusline = ' %t %= %{v:lua.markdo_demo_progress()} '
  -- Recording-only inspection keys; all Mark Do actions use the README maps.
  vim.keymap.set('n', '<leader>xh', function() vim.cmd('checkhealth markdo') end, { buffer = state.buf })
  vim.keymap.set('n', '<leader>xi', function() vim.api.nvim_echo({ { vim.fn.getreg('+') } }, false, {}) end, { buffer = state.buf })
  state.executed = {}
end
local function lines() return api.nvim_buf_get_lines(state.buf, 0, -1, false) end
local function at(row) api.nvim_win_set_cursor(state.win, { row, 2 }) end
local function progress(completed, total)
  local value = require('markdo').progress(state.buf)
  assert(value.completed == completed and value.total == total, vim.inspect(value))
end
local function inline(text)
  local ns = assert(api.nvim_get_namespaces()['markdo.inline_progress'])
  assert(vim.wait(1000, function()
    local marks = api.nvim_buf_get_extmarks(state.buf, ns, 0, -1, { details = true })
    return #marks == 1 and marks[1][4].virt_text[1][1] == text
  end, 5), text)
end
function M.press(step)
  -- Headless :feedkeys exits terminal-input mode when typeahead drains.
  -- The UI recorder sends these keys normally; its headless replay feeds the
  -- same text to the PTY directly. Every plugin action uses its real mapping.
  if step.id == 'input' then api.nvim_chan_send(vim.bo[state.term].channel, 'Neovim\n'); return end
  api.nvim_feedkeys(api.nvim_replace_termcodes(step.keys, true, false, true), 'xt', false)
end
function M.prepare(id)
  if id == 'next' then
    local health_win = api.nvim_get_current_win()
    api.nvim_set_current_win(state.win)
    if health_win ~= state.win then api.nvim_win_close(health_win, true) end
    at(1)
  elseif id == 'copy' or id == 'run' then
    at(4)
  elseif id == 'reset_task' then
    at(3)
  elseif id == 'reset_section' then
    at(1)
  elseif id == 'exit' then
    M.check_exit()
  end
end
function M.check(id)
  state.executed[id] = true
  local text = lines()
  if id == 'health' then
    assert(vim.bo.filetype == 'checkhealth')
    local report = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(report:find('recognizes tasks and fenced blocks', 1, true), report)
    assert(report:find('Clipboard provider available', 1, true), report)
    state.health_win = api.nvim_get_current_win()
  elseif id == 'next' or id == 'prev' then
    assert(api.nvim_win_get_cursor(0)[1] == 4, 'Navigation must skip the parent category')
    assert(text[3] == '- [ ] Ready for the day' and text[4] == '  - [ ] Run the greeting')
    assert(vim.fn.getreg('+') == body and vim.fn.getregtype('+') == 'v')
  elseif id == 'next_again' or id == 'next_after_done' then
    assert(api.nvim_win_get_cursor(0)[1] == 11)
    assert(vim.fn.getreg('+') == body, 'No-fence navigation must preserve the clipboard')
  elseif id == 'done_first' then
    assert(api.nvim_win_get_cursor(0)[1] == 4, 'Done must stay on the task')
    assert(text[4] == '  - [x] Run the greeting' and text[3] == '- [ ] Ready for the day')
    progress(2, 3)
  elseif id == 'inline' or id == 'progress' then
    inline('  1/2 · 50%'); progress(2, 3)
  elseif id == 'done' then
    assert(text[3] == '- [x] Ready for the day' and text[11] == '  - [x] Review the output')
    inline('  2/2 · 100%'); progress(3, 3)
  elseif id == 'focus_on' then
    assert(vim.fn.foldclosed(3) == 3 and vim.fn.foldclosedend(3) == 11)
    assert(vim.fn.foldclosed(1) == -1 and vim.fn.foldclosed(13) == -1)
    progress(3, 3)
  elseif id == 'focus_off' then
    assert(vim.fn.foldclosed(3) == -1)
    assert(api.nvim_win_get_cursor(0)[1] == 11, 'Focus must restore the previous cursor')
    inline('  2/2 · 100%'); progress(3, 3)
  elseif id == 'toggle' or id == 'undo_task' or id == 'undo_section' then
    assert(text[3] == '- [ ] Ready for the day' and text[11] == '  - [ ] Review the output')
    assert(text[4] == '  - [x] Run the greeting')
    inline('  1/2 · 50%'); progress(2, 3)
  elseif id == 'reset_task' or id == 'reset_section' then
    assert(text[4] == '  - [ ] Run the greeting' and text[11] == '  - [ ] Review the output')
    assert(text[14] == '- [x] File last run')
    inline('  0/2 · 0%'); progress(1, 3)
  elseif id == 'reset_buffer' then
    assert(text[14] == '- [ ] File last run')
    inline('  0/2 · 0%'); progress(0, 3)
  elseif id == 'copy' or id == 'clipboard' or id == 'auto_clipboard' then
    assert(vim.fn.getreg('+') == body, vim.inspect(vim.fn.getreg('+')))
    assert(vim.fn.getregtype('+') == 'v')
  elseif id == 'run' then
    assert(vim.bo.buftype == 'terminal')
    state.term, state.float = api.nvim_get_current_buf(), api.nvim_get_current_win()
    assert(vim.wait(5000, function()
      return table.concat(api.nvim_buf_get_lines(state.term, 0, -1, false), '\n'):find('Your name:', 1, true)
    end, 10))
    progress(0, 3)
  elseif id == 'input' then M.check_running_output()
  elseif id == 'exit' then M.check_exit()
  elseif id == 'normal' then assert(api.nvim_get_current_buf() == state.term)
  elseif id == 'close' then M.check_closed()
  elseif id == 'capture' then
    local data = assert(require('markdo.parse').read(state.buf))
    assert(#data.fences == 2 and data.fences[2].lang == 'text')
    assert(require('markdo.parse').body(data, data.fences[2]) == 'exit 0\n\nYour name: Neovim\nHello, Neovim!')
    assert(data.fences[2].owner == data.tasks[2])
    progress(0, 3)
  else error('Unknown demo step: ' .. id) end
  if id ~= 'health' and id ~= 'capture' then
    for _, row in ipairs({ 3, 4, 11, 14 }) do
      local col = assert(state.original[row]:find('%[[ xX]%]'))
      text[row] = text[row]:sub(1, col) .. state.original[row]:sub(col + 1, col + 1) .. text[row]:sub(col + 2)
    end
    assert(vim.deep_equal(text, state.original), 'Demo altered text outside checkbox characters')
  end
end
function M.health_details()
  for row, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find('Mark Do: Copy', 1, true) then
      api.nvim_win_set_cursor(0, { row, 0 }); vim.cmd('normal! zt'); return
    end
  end
end
function M.check_running_output()
  assert(vim.wait(1000, function()
    return table.concat(api.nvim_buf_get_lines(state.term, 0, -1, false), '\n'):find('Hello, Neovim!', 1, true)
  end, 5))
end
function M.check_exit()
  assert(vim.wait(5000, function() return vim.b[state.term].markdo_exit_code ~= nil end, 10))
  assert(vim.b[state.term].markdo_exit_code == 0)
  assert(api.nvim_win_get_config(state.float).title[1][1]:find('exit 0', 1, true))
  progress(0, 3)
end
function M.check_closed()
  assert(not api.nvim_win_is_valid(state.float))
  assert(api.nvim_get_current_buf() == state.buf)
  progress(0, 3)
  for _, row in ipairs({ 3, 4, 11, 14 }) do assert(lines()[row]:find('[ ]', 1, true)) end
  assert(vim.deep_equal(vim.fn.readfile('examples/demo.md'), state.original), 'Demo must not save checklist edits')
end
function M.verify()
  assert(vim.deep_equal(vim.fn.readfile('examples/demo.md'), state.original))
  local covered = {}
  for _, step in ipairs(M.steps) do
    assert(state.executed[step.id], 'Demo skipped ' .. step.id)
    local name = step.command and step.command:match('^(MarkDo[%w_]+)')
    if name then covered[name] = true end
  end
  for name in pairs(api.nvim_buf_get_commands(state.buf, {})) do
    if name:match('^MarkDo') and not covered[name] then
      assert(type(M.exceptions[name]) == 'string' and M.exceptions[name] ~= '',
        'Add ' .. name .. ' to the demo, or document why it is excluded in scripts/demo.lua')
    end
  end
  assert(M.steps[#M.steps].command == 'MarkDoCapture', 'End the execution chapter with Capture')
  local ran = false
  for _, step in ipairs(M.steps) do
    if step.command == 'MarkDoRun' then ran = true
    elseif ran and step.command then assert(step.command == 'MarkDoCapture', 'Execution must be the final chapter') end
  end
end
function M.finish()
  require('markdo').setup()
  if state.clipboard then
    assert(vim.fn.setreg('+', state.clipboard.value, state.clipboard.kind) == 0, 'Could not restore clipboard')
    state.clipboard = nil
  end
end
return M
