-- Called by the main suite so the documented test command covers navigation.
return function(eq, buffer, notices)
  local api = vim.api
  local md = require('markdo')
  local function pos() return api.nvim_win_get_cursor(0) end
  local function at(row, col) api.nvim_win_set_cursor(0, { row, col or 0 }) end
  local source = {
    '# Start',                    -- 1
    '- [x] checked',              -- 2
    '- [ ] parent',               -- 3
    '  continuation',             -- 4
    '  - plain',                  -- 5
    '    1) [ ] child',            -- 6
    '       continuation',        -- 7
    '       ```sh',               -- 8
    '       - [ ] code',          -- 9
    '       ```',                 -- 10
    '  - [X] checked child',      -- 11
    '',                          -- 12
    '## Later',                   -- 13
    '> 2. [ ] quoted task',       -- 14
    '',                          -- 15
    '~~~markdown',                -- 16
    '- [ ] outside code',         -- 17
    '~~~',                        -- 18
    '',                          -- 19
    '- plain',                    -- 20
    '  - [ ] final task',         -- 21
    '',                          -- 22
    'after',                      -- 23
  }
  local buf = buffer(source)
  for _, suffix in ipairs({ 'Next', 'Prev' }) do
    eq(vim.fn.exists(':MarkDo' .. suffix), 2)
    local mapping = vim.fn.maparg('<Plug>(MarkDo' .. suffix .. ')', 'n', false, true)
    eq(mapping.buffer, 1)
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  local sequence = vim.fn.undotree().seq_cur
  local modified = vim.bo.modified
  vim.fn.setreg('/', 'unchanged search')
  vim.cmd.MarkDoNext(); eq(pos(), { 6, 7 })
  eq(api.nvim_buf_get_mark(buf, "'"), { 1, 0 })
  vim.cmd.MarkDoNext(); eq(pos(), { 14, 5 })
  md.next(); eq(pos(), { 21, 4 })
  local before = pos()
  md.next(); eq(pos(), before); eq(notices[#notices], 'Mark Do: No next unfinished task')
  vim.cmd.MarkDoPrev(); eq(pos(), { 14, 5 })
  md.prev(); eq(pos(), { 6, 7 })
  before = pos()
  md.prev(); eq(pos(), before); eq(notices[#notices], 'Mark Do: No previous unfinished task')
  -- A task's own line is skipped regardless of column. From continuation or
  -- code, Prev can return to that task's checkbox, while Next moves ahead.
  at(6, 0); md.next(); eq(pos(), { 14, 5 })
  at(6, 12); md.prev(); eq(pos(), { 6, 12 })
  at(7); md.prev(); eq(pos(), { 6, 7 })
  at(9); md.prev(); eq(pos(), { 6, 7 })
  at(9); md.next(); eq(pos(), { 14, 5 })
  at(12); md.next(); eq(pos(), { 14, 5 })
  at(12); md.prev(); eq(pos(), { 6, 7 })
  at(23); md.prev(); eq(pos(), { 21, 4 })
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), source)
  eq(api.nvim_buf_get_changedtick(buf), tick)
  eq(vim.fn.undotree().seq_cur, sequence)
  eq(vim.bo.modified, modified)
  eq(vim.fn.getreg('/'), 'unchanged search')
  -- Restoring parent stops is explicit; checked descendants still make a
  -- checkbox a parent, while plain list children alone do not.
  md.setup({ navigation = { leaf_only = false } })
  at(1); md.next(); eq(pos(), { 3, 2 })
  md.next(); eq(pos(), { 6, 7 }); md.prev(); eq(pos(), { 3, 2 })
  md.setup()
  -- Reparse unsaved edits; completed tasks are skipped and reopened ones return.
  api.nvim_buf_set_text(buf, 5, 8, 5, 9, { 'x' })
  at(3); md.next(); eq(pos(), { 14, 5 })
  api.nvim_buf_set_text(buf, 1, 3, 1, 4, { ' ' })
  at(3); md.prev(); eq(pos(), { 2, 2 })
  buffer({ '# Heading', '- [ ] category', '  - [X] completed child', '- [x] checked category',
    '  - [ ] real work', '- [ ] plain children', '  - just text', '    continuation' })
  md.next(); eq(pos(), { 5, 4 })
  md.next(); eq(pos(), { 6, 2 })
  md.prev(); eq(pos(), { 5, 4 })
  -- Classification follows unsaved nesting edits in both directions.
  api.nvim_buf_set_lines(0, 2, 3, false, {})
  at(1); md.next(); eq(pos(), { 2, 2 })
  -- Both motions work without a task at the cursor and without a match.
  buffer({ '# No tasks', '- plain', '```', '- [ ] code', '```' })
  before = pos()
  md.next(); eq(pos(), before); eq(notices[#notices], 'Mark Do: No next unfinished task')
  md.prev(); eq(pos(), before); eq(notices[#notices], 'Mark Do: No previous unfinished task')
  buffer({ '- [x] complete', '- [X] also complete' })
  md.next(); eq(pos(), { 1, 0 })
  -- The new commands and mappings are absent from non-Markdown buffers.
  vim.cmd.enew({ bang = true }); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoNext'), 0); eq(vim.fn.exists(':MarkDoPrev'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoNext)', 'n'), '')
  eq(vim.fn.maparg('<Plug>(MarkDoPrev)', 'n'), '')
  -- Reveal a destination in a closed fold, even in a nonmodifiable buffer.
  buffer({ '# Heading', '', '- [ ] folded', '  text' })
  vim.wo.foldmethod = 'manual'; vim.cmd('3,4fold'); at(1)
  eq(vim.fn.foldclosed(3), 3)
  vim.bo.modifiable = false
  md.next(); eq(pos(), { 3, 2 }); eq(vim.fn.foldclosed(3), -1)
  vim.bo.modifiable = true
  -- Missing parsers have the same actionable error as the other commands.
  local get_parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('parser unavailable') end
  before = pos(); md.next(); eq(pos(), before)
  eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  md.prev(); eq(pos(), before)
  vim.treesitter.get_parser = get_parser
  -- Setup validates atomically and can restore defaults after live changes.
  md.setup({ navigation = { leaf_only = false } })
  for _, opts in ipairs({ false, 'bad', { navigation = false }, { navigation = { leaf_only = 'yes' } },
    { navigation = { copy_on_jump = 1 } }, { navigation = { typo = true } }, { typo = true } }) do
    local ok, err = pcall(md.setup, opts)
    eq(ok, false); eq(tostring(err):find('markdo.setup:', 1, true) ~= nil, true)
  end
  buffer({ '# Heading', '- [ ] parent', '  - [ ] child' })
  md.next(); eq(pos(), { 2, 2 }) -- Invalid setup did not partly replace settings.
  md.setup({}); at(1); md.next(); eq(pos(), { 3, 4 })
end
