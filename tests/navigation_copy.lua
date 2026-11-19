-- Isolate the clipboard provider cache from the rest of the suite.
vim.opt.rtp:prepend(vim.fn.getcwd())
local api, md = vim.api, require('markdo')
local count, writes, notices = 0, 0, {}
local clipboard = { { 'previous clipboard' }, 'v' }
vim.g.clipboard = { name = 'navigation fixture', cache_enabled = 0,
  copy = { ['+'] = function(lines, kind) writes = writes + 1; clipboard = { vim.deepcopy(lines), kind } end,
    ['*'] = function() error('navigation must not write primary selection') end },
  paste = { ['+'] = function() return vim.deepcopy(clipboard) end, ['*'] = function() return { { '' }, 'v' } end } }
vim.notify = function(s) notices[#notices + 1] = s end
vim.ui.select = function() error('navigation must never open a fence picker') end
local function eq(a, b)
  count = count + 1
  assert(vim.deep_equal(a, b), ('navigation copy check %d: expected %s; got %s'):format(count, vim.inspect(b), vim.inspect(a)))
end
local function at(row) api.nvim_win_set_cursor(0, { row, 0 }) end
local function row() return api.nvim_win_get_cursor(0)[1] end
local function buffer(lines)
  vim.cmd.enew({ bang = true }); vim.bo.filetype = 'markdown'
  api.nvim_buf_set_lines(0, 0, -1, false, lines); at(1)
end
local source = { '# Start', '- [ ] group', '  - [ ] first', '    ~~~python extra',
  '    first', '', '      second # comment', '    ', '    ~~~',
  '  - [ ] no fence', '  - [ ] last', '    ```', '    final', '    ```' }
buffer(source)
vim.fn.setreg('a', 'named register'); vim.fn.setreg('"', 'unnamed register')
local has, probes = vim.fn.has, 0
vim.fn.has = function(feature)
  if feature == 'clipboard' then probes = probes + 1 end
  return has(feature)
end
md.next(); eq(row(), 3); eq(writes, 0); eq(probes, 0) -- Defaults do not even probe the provider.
md.setup({ navigation = { copy_on_jump = true } })
at(1)
local tick, sequence, modified = api.nvim_buf_get_changedtick(0), vim.fn.undotree().seq_cur, vim.bo.modified
vim.fn.setreg('/', 'keep search')
md.next(); eq(row(), 3)
eq(clipboard, { { 'first', '', '  second # comment', '' }, 'v' }); eq(writes, 1)
eq(vim.fn.getreg('+'), 'first\n\n  second # comment\n'); eq(vim.fn.getregtype('+'), 'v')
eq(vim.fn.getreg('a'), 'named register'); eq(vim.fn.getreg('"'), 'unnamed register')
md.next(); eq(row(), 10); eq(writes, 1) -- No fence does not borrow the sibling's fence.
md.next(); eq(row(), 11); eq(clipboard, { { 'final' }, 'v' }); eq(writes, 2)
md.next(); eq(row(), 11); eq(writes, 2) -- A boundary is not a successful jump.
md.prev(); eq(row(), 10); eq(writes, 2)
md.prev(); eq(row(), 3); eq(writes, 3)
eq(api.nvim_buf_get_lines(0, 0, -1, false), source)
eq(api.nvim_buf_get_changedtick(0), tick); eq(vim.fn.undotree().seq_cur, sequence)
eq(vim.bo.modified, modified); eq(vim.fn.getreg('/'), 'keep search')
-- A same-line motion that cannot advance does not recopy; continuation Prev can.
md.prev(); eq(row(), 3); eq(writes, 3)
at(7); md.prev(); eq(row(), 3); eq(writes, 4)
-- Body extraction reads unsaved edits and works in nonmodifiable/folded views.
api.nvim_buf_set_lines(0, 4, 5, false, { '    freshly edited' })
vim.wo.foldmethod = 'manual'; vim.cmd('3,9fold'); at(1); vim.bo.modifiable = false
md.next(); eq(row(), 3); eq(vim.fn.foldclosed(3), -1)
eq(clipboard[1][1], 'freshly edited'); vim.bo.modifiable = true
-- Empty, incomplete and ambiguous scopes leave the clipboard alone, without UI.
for _, body in ipairs({
  {}, { '  ```', '  ', '  ```' }, { '  ```sh', '  incomplete' },
  { '  ```sh', '  one', '  ```', '  ~~~', '  two', '  ~~~' },
  { '  ```sh', '  one', '  ```', '  ```', '', '  ```' },
}) do
  local fixture = { '# Heading', '- [ ] task' }; vim.list_extend(fixture, body)
  buffer(fixture)
  local before, notifications = writes, #notices
  md.next(); eq(row(), 2); eq(writes, before); eq(#notices, notifications)
end
buffer({ '# Heading', '- [ ] parent', '  ```sh', '  parent code', '  ```', '  - [ ] child' })
local before = writes
md.next(); eq(row(), 6); eq(writes, before) -- No ancestor fence inheritance.
-- Explicitly including parents uses the destination's own fence, too.
md.setup({ navigation = { leaf_only = false, copy_on_jump = true } })
at(1); md.next(); eq(row(), 2); eq(clipboard, { { 'parent code' }, 'v' })
-- Missing/failing providers never undo or cancel the motion.
md.setup({ navigation = { copy_on_jump = true } })
buffer({ '# Heading', '- [ ] task', '  ```sh', '  hello', '  ```' })
local old_clipboard = vim.deepcopy(clipboard)
vim.fn.has = function(feature) if feature == 'clipboard' then return 0 end; return has(feature) end
md.next(); eq(row(), 2); eq(notices[#notices]:find('No clipboard provider', 1, true) ~= nil, true)
eq(clipboard, old_clipboard)
vim.fn.has = has
local setreg = vim.fn.setreg
for _, failure in ipairs({ function() error('provider failed') end, function() return 1 end }) do
  vim.fn.setreg = failure
  at(1); md.next(); eq(row(), 2); eq(notices[#notices]:find('Clipboard failed', 1, true) ~= nil, true)
  eq(clipboard, old_clipboard)
end
vim.fn.setreg = setreg
-- Turning the option off takes effect immediately. Done/Toggle never copy.
md.setup(); at(1); before = writes; md.next(); eq(writes, before)
md.setup({ navigation = { copy_on_jump = true } })
local cursor = api.nvim_win_get_cursor(0)
md.done(); eq(api.nvim_win_get_cursor(0), cursor); eq(writes, before)
md.toggle(); eq(api.nvim_win_get_cursor(0), cursor); eq(writes, before)
-- The compatibility DoneNext command keeps parent stops and has no copy side effect.
buffer({ '- [X] current', '- [ ] parent', '  ```sh', '  parent code', '  ```', '  - [ ] child' })
md.done_next(); eq(row(), 2); eq(writes, before)
md.setup()
print(('Mark Do: %d copy-on-navigation checks passed'):format(count))
vim.cmd.qa({ bang = true })
