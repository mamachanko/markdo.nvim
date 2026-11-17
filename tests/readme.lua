-- Execute the README's actual snippets and sample against the plugin.
local api = vim.api
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local readme = table.concat(vim.fn.readfile('README.md'), '\n')
local function example(name, lang, fence)
  fence = fence or '```'
  local tail = assert(readme:match('<!%-%- example:' .. name .. ' %-%->\n(.*)'), name)
  return assert(tail:match('^' .. fence .. lang .. '\n(.-)\n' .. fence), name)
end
local lazy = assert(loadstring('return ' .. example('lazy', 'lua')))()
assert(lazy[1] == 'mamachanko/markdo.nvim' and lazy.ft == 'markdown')
-- Execute the native shell example with a local clone instead of network access.
local temp = vim.fn.tempname()
local native = example('native', 'sh'):gsub('https://github.com/mamachanko/markdo.nvim.git', function() return vim.fn.shellescape(root) end)
local old_data = vim.env.XDG_DATA_HOME
vim.env.XDG_DATA_HOME = temp
local result = vim.fn.system({ 'sh', '-c', native })
vim.env.XDG_DATA_HOME = old_data
assert(vim.v.shell_error == 0, result)
local site = temp .. '/nvim/site'
assert(vim.fn.filereadable(site .. '/pack/plugins/start/markdo.nvim/plugin/markdo.lua') == 1)
vim.opt.packpath:prepend(site)
vim.cmd.packloadall()
-- Verify Markdown-only keymaps from the documented init.lua snippet.
assert(loadstring(example('keymaps', 'lua')))()
local runbook = example('runbook', 'markdown', '````')
assert(runbook == table.concat(vim.fn.readfile('examples/runbook.md'), '\n'))
vim.cmd.enew()
vim.bo.filetype = 'text'
assert(vim.fn.maparg('<leader>xd', 'n') == '')
api.nvim_buf_set_lines(0, 0, -1, false, vim.split(runbook, '\n', { plain = true }))
vim.bo.filetype = 'markdown'
assert(vim.fn.exists(':MarkDoDone') == 2)
for key, action in pairs({ xx = 'Toggle', xd = 'Done', xj = 'DoneNext', xr = 'Reset', xf = 'FocusToggle', xc = 'Copy', xe = 'Run', xo = 'Capture', xn = 'Next', xp = 'Prev', xs = 'Progress', xv = 'ProgressToggle' }) do
  local mapping = vim.fn.maparg('<leader>' .. key, 'n', false, true)
  assert(mapping.buffer == 1 and mapping.rhs == '<Plug>(MarkDo' .. action .. ')')
end
local copied
vim.g.clipboard = { name = 'README test', cache_enabled = 0,
  copy = { ['+'] = function(ls, rt) copied = { ls, rt } end, ['*'] = function() end },
  paste = { ['+'] = function() return { { '' }, 'v' } end, ['*'] = function() return { { '' }, 'v' } end } }
local function at(row) api.nvim_win_set_cursor(0, { row, 2 }) end
local function key(suffix) api.nvim_feedkeys('\\x' .. suffix, 'xt', false) end
local function content() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
assert(loadstring(example('statusline', 'lua')))()
assert(_G.markdo_progress() == '0/2 (0%)')
-- Copy first, then work through tasks with the documented optional keys.
at(4); key('c')
assert(vim.deep_equal(copied, { { 'name=Neovim', [[printf 'Hello, %s!\n' "$name"]], 'sleep 1' }, 'v' }))
key('j')
assert(api.nvim_win_get_cursor(0)[1] == 10)
assert(api.nvim_buf_get_lines(0, 3, 4, false)[1] == '  - [x] Run the greeting')
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [ ] Ready for the day')
assert(_G.markdo_progress() == '1/2 (50%)')
key('p'); assert(api.nvim_win_get_cursor(0)[1] == 3)
key('n'); assert(api.nvim_win_get_cursor(0)[1] == 10)
key('d')
assert(api.nvim_get_current_line() == '  - [x] Review the output')
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [x] Ready for the day')
local completed = example('completed', 'markdown')
for task in completed:gmatch('[^\n]+') do
  if task:find('%[x%]') then assert(vim.tbl_contains(api.nvim_buf_get_lines(0, 0, -1, false), task)) end
end
-- Inspect buffer, statusline and inline progress, then reopen and undo.
assert(_G.markdo_progress() == '2/2 (100%)')
assert(api.nvim_eval_statusline('%{v:lua.markdo_progress()}', {}).str == '2/2 (100%)')
local notify, summary = vim.notify
vim.notify = function(text) summary = text end
key('s'); assert(summary == 'Mark Do: 2/2 tasks complete (100%)')
vim.notify = notify
key('v')
local inline_ns = assert(api.nvim_get_namespaces()['markdo.inline_progress'])
local function inline_text()
  local marks = api.nvim_buf_get_extmarks(0, inline_ns, 0, -1, { details = true })
  return marks[1] and marks[1][4].virt_text[1][1]
end
assert(inline_text() == '  2/2 · 100%')
key('x'); assert(_G.markdo_progress() == '1/2 (50%)')
vim.cmd.undo(); assert(_G.markdo_progress() == '2/2 (100%)')
assert(vim.wait(1000, function() return inline_text() == '  2/2 · 100%' end, 5))
-- Focus completed branches, then restore the view before resetting.
local focus_cursor = api.nvim_win_get_cursor(0)
key('f')
assert(vim.fn.foldclosed(3) == 3 and vim.fn.foldclosedend(3) == 10)
assert(vim.fn.foldclosed(1) == -1)
key('f')
assert(vim.fn.foldclosed(3) == -1)
assert(vim.deep_equal(api.nvim_win_get_cursor(0), focus_cursor))
-- Reopen the sample with each reset scope; every reset is one undo step.
at(3); key('r')
assert(content() == runbook and api.nvim_win_get_cursor(0)[1] == 3)
vim.cmd.undo(); assert(require('markdo').progress().percent == 100)
key('1'); assert(content() == runbook)
vim.cmd.undo(); key('2'); assert(content() == runbook)
key('v'); assert(inline_text() == nil)
-- End with execution and capture. Neither changes checklist states.
at(4)
local source = api.nvim_get_current_buf()
key('e')
local term, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 10))
assert(vim.b[term].markdo_exit_code == 0)
assert(table.concat(api.nvim_buf_get_lines(term, 0, -1, false), '\n'):find('Hello, Neovim!', 1, true))
assert(table.concat(api.nvim_buf_get_lines(source, 0, -1, false), '\n') == runbook)
vim.cmd.stopinsert()
for _, mapping in ipairs(api.nvim_buf_get_keymap(term, 'n')) do if mapping.lhs == 'q' then mapping.callback() end end
assert(not api.nvim_win_is_valid(win))
key('o')
local capture_example = example('captured', 'markdown', '````')
assert(content():find(capture_example, 1, true))
assert(require('markdo').progress().percent == 0)
vim.cmd.undo(); assert(content() == runbook)
vim.cmd.enew({ bang = true }); vim.bo.filetype = 'markdown'
assert(_G.markdo_progress() == '')
vim.bo.filetype = 'text'; assert(_G.markdo_progress() == '')
vim.fn.delete(temp, 'rf')
print('README installation, mappings and all quick-start examples passed, ending with Run and Capture')
vim.cmd.qa({ bang = true })
