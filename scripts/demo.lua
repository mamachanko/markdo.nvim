-- Shared, assertion-backed walkthrough for the real UI recorder and headless CI.
local M = {}
local api = vim.api
local state = {}
local body = [[printf 'Your name: '
read name
printf 'Hello, %s!\n' "$name"
sleep 1]]
-- New commands must be covered below or have an explicit reviewed exception.
M.exceptions = {}
M.steps = {
  { id = 'health', command = 'checkhealth markdo', hold = 1500 },
  { id = 'next', command = 'MarkDoNext', hold = 1100 },
  { id = 'prev', command = 'MarkDoPrev', hold = 1100 },
  { id = 'done_next', command = 'MarkDoDoneNext', hold = 1400 },
  { id = 'inline', command = 'MarkDoProgressToggle', hold = 1500 },
  { id = 'progress', command = 'MarkDoProgress', hold = 1600 },
  { id = 'done', command = 'MarkDoDone', hold = 1500 },
  { id = 'focus_on', command = 'MarkDoFocusToggle', hold = 1500 },
  { id = 'focus_off', command = 'MarkDoFocusToggle', hold = 1500 },
  { id = 'toggle', command = 'MarkDoToggle', hold = 1400 },
  { id = 'reset_task', command = 'MarkDoReset', hold = 1300 },
  { id = 'undo_task', command = 'undo', hold = 800 },
  { id = 'reset_section', command = 'MarkDoReset section', hold = 1300 },
  { id = 'undo_section', command = 'undo', hold = 800 },
  { id = 'reset_buffer', command = 'MarkDoReset buffer', hold = 1500 },
  { id = 'copy', command = 'MarkDoCopy', hold = 800 },
  { id = 'clipboard', command = "echo getreg('+')", hold = 1800, message = true },
  { id = 'run', command = 'MarkDoRun', hold = 1500 },
}

function M.setup(opts)
  opts = opts or {}
  vim.opt.rtp:prepend(vim.fn.getcwd())
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
  state.buf, state.win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  state.original = vim.fn.readfile('examples/demo.md')
  assert(#state.original == 14, 'Update demo row assertions when changing its fixture')
  api.nvim_win_set_cursor(0, { 3, 2 })
  -- Optional README statusline integration, configured before the walkthrough.
  _G.markdo_demo_progress = function()
    if vim.bo.filetype ~= 'markdown' then return '' end
    local p = require('markdo').progress()
    return p and p.percent and ('%d/%d (%d%%)'):format(p.completed, p.total, p.percent) or ''
  end
  vim.opt.statusline = ' %t %= %{v:lua.markdo_demo_progress()} '
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
function M.prepare(id)
  if id == 'next' then
    local health_win = api.nvim_get_current_win()
    api.nvim_set_current_win(state.win)
    if health_win ~= state.win then api.nvim_win_close(health_win, true) end
    at(3)
  elseif id == 'done_next' or id == 'copy' or id == 'run' then
    at(4)
  elseif id == 'reset_task' then
    at(3)
  elseif id == 'reset_section' then
    at(1)
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
  elseif id == 'next' then assert(api.nvim_win_get_cursor(0)[1] == 4)
  elseif id == 'prev' then assert(api.nvim_win_get_cursor(0)[1] == 3)
  elseif id == 'done_next' then
    assert(api.nvim_win_get_cursor(0)[1] == 11)
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
  elseif id == 'copy' or id == 'clipboard' then
    assert(vim.fn.getreg('+') == body, vim.inspect(vim.fn.getreg('+')))
    assert(vim.fn.getregtype('+') == 'v')
  elseif id == 'run' then
    assert(vim.bo.buftype == 'terminal')
    state.term, state.float = api.nvim_get_current_buf(), api.nvim_get_current_win()
    assert(vim.wait(5000, function()
      return table.concat(api.nvim_buf_get_lines(state.term, 0, -1, false), '\n'):find('Your name:', 1, true)
    end, 10))
    progress(0, 3)
  else error('Unknown demo step: ' .. id) end
  if id ~= 'health' then
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
function M.send_input()
  api.nvim_chan_send(vim.bo[state.term].channel, 'Neovim\n')
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
function M.close_terminal()
  vim.cmd.stopinsert()
  for _, key in ipairs(api.nvim_buf_get_keymap(state.term, 'n')) do
    if key.lhs == 'q' then key.callback(); return end
  end
end
function M.check_closed()
  assert(not api.nvim_win_is_valid(state.float))
  assert(api.nvim_get_current_buf() == state.buf)
  progress(0, 3)
  for _, row in ipairs({ 3, 4, 11, 14 }) do assert(lines()[row]:find('[ ]', 1, true)) end
  assert(vim.deep_equal(vim.fn.readfile('examples/demo.md'), state.original), 'Demo must not save checklist edits')
  local covered = {}
  for _, step in ipairs(M.steps) do
    assert(state.executed[step.id], 'Demo skipped ' .. step.id)
    local name = step.command:match('^(MarkDo[%w_]+)')
    if name then covered[name] = true end
  end
  for name in pairs(api.nvim_buf_get_commands(state.buf, {})) do
    if name:match('^MarkDo') and not covered[name] then
      assert(type(M.exceptions[name]) == 'string' and M.exceptions[name] ~= '',
        'Add ' .. name .. ' to the demo, or document why it is excluded in scripts/demo.lua')
    end
  end
  assert(M.steps[#M.steps].command == 'MarkDoRun', 'Execution must be the final demo chapter')
end
function M.finish()
  if state.clipboard then
    assert(vim.fn.setreg('+', state.clipboard.value, state.clipboard.kind) == 0, 'Could not restore clipboard')
    state.clipboard = nil
  end
end
return M
