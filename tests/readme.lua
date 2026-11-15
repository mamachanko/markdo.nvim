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
for key, action in pairs({ xx = 'Toggle', xd = 'Done', xc = 'Copy', xe = 'Run' }) do
  local mapping = vim.fn.maparg('<leader>' .. key, 'n', false, true)
  assert(mapping.buffer == 1 and mapping.rhs == '<Plug>(MarkDo' .. action .. ')')
end
local copied
vim.g.clipboard = { name = 'README test', cache_enabled = 0,
  copy = { ['+'] = function(ls, rt) copied = { ls, rt } end, ['*'] = function() end },
  paste = { ['+'] = function() return { { '' }, 'v' } end, ['*'] = function() return { { '' }, 'v' } end } }
api.nvim_win_set_cursor(0, { 4, 0 })
local source = api.nvim_get_current_buf()
vim.api.nvim_feedkeys('\\xe', 'xt', false)
local term, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 10))
assert(vim.b[term].markdo_exit_code == 0)
assert(table.concat(api.nvim_buf_get_lines(term, 0, -1, false), '\n'):find('Hello, Neovim!', 1, true))
assert(api.nvim_buf_get_lines(source, 2, 3, false)[1] == '- [ ] Ready for the day')
vim.cmd.stopinsert()
for _, mapping in ipairs(api.nvim_buf_get_keymap(term, 'n')) do if mapping.lhs == 'q' then mapping.callback() end end
assert(not api.nvim_win_is_valid(win))
api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_feedkeys('\\xc', 'xt', false)
assert(vim.deep_equal(copied, { { 'name=Neovim', [[printf 'Hello, %s!\n' "$name"]], 'sleep 1' }, 'v' }))
vim.api.nvim_feedkeys('\\xd', 'xt', false)
assert(api.nvim_get_current_line() == '  - [x] Run the greeting')
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [ ] Ready for the day')
api.nvim_win_set_cursor(0, { 10, 0 }); vim.cmd.MarkDoDone()
assert(api.nvim_get_current_line() == '  - [x] Review the output')
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [x] Ready for the day')
local completed = example('completed', 'markdown')
for task in completed:gmatch('[^\n]+') do
  if task:find('%[x%]') then assert(vim.tbl_contains(api.nvim_buf_get_lines(0, 0, -1, false), task)) end
end
vim.api.nvim_feedkeys('\\xx', 'xt', false)
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [ ] Ready for the day')
vim.cmd.undo()
assert(api.nvim_buf_get_lines(0, 9, 10, false)[1] == '  - [x] Review the output')
assert(api.nvim_buf_get_lines(0, 2, 3, false)[1] == '- [x] Ready for the day')
vim.fn.delete(temp, 'rf')
print('README install, keymap, Copy, Run, Done, and roll-up examples passed')
vim.cmd.qa({ bang = true })
