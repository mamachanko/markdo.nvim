vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local count = 0
local function eq(a, b)
  count = count + 1
  assert(vim.deep_equal(a, b), ('check %d\nexpected %s\ngot %s'):format(count, vim.inspect(b), vim.inspect(a)))
end
local notices = {}
vim.notify = function(s) notices[#notices + 1] = s end
local function buffer(lines, row)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = 'markdown'
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  api.nvim_win_set_cursor(0, { row or 1, 0 })
  return api.nvim_get_current_buf()
end
-- Also attach to Markdown buffers opened before plugin loading.
buffer({ '- [ ] old' })
vim.cmd('runtime plugin/markdo.lua')
eq(vim.fn.exists(':MarkDoDone'), 2)
eq(vim.fn.exists(':MarkDoDoneNext'), 2)
eq(vim.fn.exists(':MarkDoReset'), 2)
eq(vim.fn.exists(':MarkDoFocusToggle'), 2)
eq(vim.fn.exists(':MarkDoCapture'), 2)
eq(vim.fn.exists(':MarkDoProgress'), 2)
eq(vim.fn.exists(':MarkDoProgressToggle'), 2)
eq(vim.fn.exists(':MarkDoNext'), 2); eq(vim.fn.exists(':MarkDoPrev'), 2)
local md = require('markdo')
local parse = require('markdo.parse')
local function lines() return api.nvim_buf_get_lines(0, 0, -1, false) end
local original = { '- [ ] root', '  - plain', '    1. [ ] child', '       continuation', '', '       ```sh', '       # [ ] code', '       ```', '', '- [ ] sibling' }
buffer(original, 4)
local pos = api.nvim_win_get_cursor(0)
md.done()
eq(lines()[1], '- [x] root'); eq(lines()[3], '    1. [x] child'); eq(api.nvim_win_get_cursor(0), pos)
vim.cmd.undo(); eq(lines(), original)
api.nvim_win_set_cursor(0, { 4, 0 }); md.done(); md.toggle(); eq(lines(), original)
vim.cmd.undo(); eq(lines()[1], '- [x] root'); eq(lines()[3], '    1. [x] child')
api.nvim_win_set_cursor(0, { 1, 0 }); md.toggle()
eq(lines()[1], '- [ ] root'); eq(lines()[3], '    1. [x] child')
api.nvim_win_set_cursor(0, { 7, 0 }); md.toggle(); eq(lines()[3], '    1. [ ] child')
api.nvim_win_set_cursor(0, { 9, 0 }); local before = lines(); md.toggle(); eq(lines(), before)
buffer({ '1) [X] a', '   continuation', '2) [ ] b' }, 2); md.done(); eq(lines()[1], '1) [X] a'); md.toggle(); eq(lines()[1], '1) [ ] a')
buffer({ '- [ ] parent', '  - [ ] child', '    ```sh', '    hi', '    ```' })
local data = assert(parse.read(0)); local chosen, why
parse.select(data, 0, function(f, e) chosen, why = f, e end); eq(chosen, nil); assert(why:find('No fence'))
parse.select(data, 1, function(f) chosen = f end); eq(chosen.owner.row, 1)
-- Pin the minimum-version parser's structural interpretation with a fixture.
buffer(vim.fn.readfile('tests/fixtures/structure.md'))
data = assert(parse.read(0))
eq(#data.tasks, 3); eq(#data.fences, 2); eq(data.tasks[2].parent, data.tasks[1])
eq(data.fences[1].owner, data.tasks[2]); eq(data.headings, { 0, 15 })
eq(data:task_at(3), data.tasks[1]); eq(data:task_at(12), nil)
eq(data:task_at(9), data.tasks[2])
eq(assert(parse.body(data, data.fences[1])), '# - [ ] code, not a task\necho hello')
-- Internal blank paragraphs belong to a task; blank sibling separators do not.
buffer({ '- [ ] parent', '  first', '', '  second', '', '- [ ] sibling' }, 3)
md.done(); eq(lines()[1], '- [x] parent')
api.nvim_win_set_cursor(0, { 5, 0 }); md.toggle(); eq(lines()[1], '- [x] parent')
dofile('tests/navigation.lua')(eq, buffer, notices)
dofile('tests/done_next.lua')(eq, buffer, notices)
dofile('tests/reset.lua')(eq, buffer, notices)
dofile('tests/focus.lua')(eq, buffer, notices)
dofile('tests/progress.lua')(eq, buffer, notices)
dofile('tests/inline.lua')(eq, buffer, notices)
dofile('tests/health.lua')(eq)
-- Clipboard provider stub: preserve all other registers and exact characterwise body.
local copied
vim.g.clipboard = { name = 'test', copy = { ['+'] = function(ls, rt) copied = { ls, rt } end, ['*'] = function() end },
  paste = { ['+'] = function() return { { '' }, 'v' } end, ['*'] = function() return { { '' }, 'v' } end }, cache_enabled = 0 }
vim.fn.setreg('a', 'untouched')
buffer({ '- [ ] task', '  ~~~bash extra', '  var="hello"', '', '    echo "$var" # comment', '  ~~~' }, 6)
md.copy(); eq(copied, { { 'var="hello"', '', '  echo "$var" # comment' }, 'v' }); eq(vim.fn.getreg('a'), 'untouched')
buffer({ '```', 'raw', '```' }, 1); md.copy(); eq(copied, { { 'raw' }, 'v' })
buffer({ ' > - [ ] task', ' >     ```sh', ' >     a', ' >       b', ' >', ' >     ```' }, 3)
md.copy(); eq(copied, { { 'a', '  b', '' }, 'v' })
buffer({ '  ```sh', ' a', '    b', '', '  ```' }); md.copy(); eq(copied, { { 'a', '  b', '' }, 'v' })
buffer({ '```sh', 'echo incomplete' }); local prior = vim.deepcopy(copied); md.copy(); eq(copied, prior); assert(notices[#notices]:find('Incomplete'))
buffer({ '```sh', '', '```' }); md.copy(); assert(notices[#notices]:find('Empty'))
-- Section boundaries include deeper headings and preamble.
buffer({ 'preamble', '# first', '```sh', 'one', '```', '## child', '```sh', 'two', '```' })
data = assert(parse.read(0)); chosen = nil
parse.select(data, 0, function(f) chosen = f end); eq(chosen, nil)
parse.select(data, 1, function(f) chosen = f end); eq(chosen.row, 2)
parse.select(data, 4, function(f) chosen = f end); eq(chosen.row, 2) -- closing delimiter
-- Async picker cancellation, stale edits and deleted buffers.
local pending
vim.ui.select = function(items, opts, cb) pending = { items, cb }; assert(opts.format_item(items[1]):find('sh')) end
local pickerlines = { '- [ ] task', '  ```sh', '  one', '  ```', '  ```bash', '  two', '  ```' }
buffer(pickerlines); md.copy(); pending[2](nil); eq(copied, prior)
md.copy(); api.nvim_buf_set_lines(0, 2, 3, false, { '  changed' }); pending[2](pending[1][1]); assert(notices[#notices]:find('retry')); eq(copied, prior)
local b = buffer(pickerlines); md.copy(); api.nvim_buf_delete(b, { force = true }); pending[2](pending[1][1]); assert(notices[#notices]:find('retry'))
buffer(pickerlines); md.copy(); pending[2](pending[1][2]); eq(copied, { { 'two' }, 'v' })
-- Explicit execution uses one interpreter, retains output, and never checks tasks.
local source = buffer({ '- [ ] run', '  ```sh', '  value=markdo', '  printf "%s\\n" "$value"', '  printf "errline\\n" >&2', '  exit 7', '  ```' })
md.run()
local term = api.nvim_get_current_buf(); local win = api.nvim_get_current_win()
assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 10))
eq(vim.b[term].markdo_exit_code, 7)
local output = table.concat(api.nvim_buf_get_lines(term, 0, -1, false), '\n')
assert(output:find('markdo'), output); assert(output:find('errline'), output)
assert(api.nvim_win_get_config(win).title[1][1]:find('exit 7'))
eq(api.nvim_buf_get_lines(source, 0, 1, false)[1], '- [ ] run')
vim.cmd.stopinsert()
local function key(buf, lhs)
  for _, mapping in ipairs(api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs == lhs then mapping.callback(); return end
  end
  error('missing mapping: ' .. lhs)
end
key(term, 'q'); eq(api.nvim_win_is_valid(win), false)
-- Active second run focuses existing job; closing stops it.
buffer({ '```sh', 'sleep 30', '```' }); md.run(); term = api.nvim_get_current_buf(); win = api.nvim_get_current_win()
api.nvim_set_current_win(vim.fn.win_getid(1)); md.run(); eq(api.nvim_get_current_win(), win)
api.nvim_win_close(win, true)
assert(vim.wait(5000, function() return not require('markdo.runner').focus() end, 10))
-- Stop retains output, q is inactive while running, then closes after exit.
buffer({ '```sh', 'echo stopping; sleep 30', '```' }); md.run()
term = api.nvim_get_current_buf(); win = api.nvim_get_current_win()
assert(vim.wait(2000, function()
  return table.concat(api.nvim_buf_get_lines(term, 0, -1, false), '\n'):find('stopping') ~= nil
end, 10))
key(term, 'q'); eq(api.nvim_win_is_valid(win), true)
key(term, 'x')
assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 10))
eq(api.nvim_win_is_valid(win), true)
assert(table.concat(api.nvim_buf_get_lines(term, 0, -1, false), '\n'):find('stopping'))
key(term, 'q'); eq(api.nvim_win_is_valid(win), false)
-- Refuse invalid interpreters without launching a float.
buffer({ '```python', 'print(1)', '```' }); local sourcewin = api.nvim_get_current_win(); md.run()
eq(api.nvim_get_current_win(), sourcewin); assert(notices[#notices]:find('Unsupported'))
local saved_shell = vim.o.shell
vim.o.shell = '/nonexistent-markdo-shell'
buffer({ '```shell', 'echo hello', '```' }); md.run(); assert(notices[#notices]:find('missing'))
vim.o.shell = saved_shell
-- Report the parser dependency instead of silently falling back.
dofile('tests/capture.lua')(eq, buffer, notices)
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function() error('parser unavailable') end
md.done(); assert(notices[#notices]:find('TSInstall markdown'))
vim.treesitter.get_parser = get_parser
local isolated = vim.fn.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-l', 'tests/no_clipboard.lua' })
assert(vim.v.shell_error == 0, isolated)
local health_output = vim.fn.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-l', 'tests/health_command.lua' })
assert(vim.v.shell_error == 0, health_output)
local demo_output = vim.fn.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-l', 'tests/demo.lua' })
assert(vim.v.shell_error == 0, demo_output)
print(('Mark Do: %d checks passed on %s'):format(count, tostring(vim.version())))
vim.cmd.qa({ bang = true })
