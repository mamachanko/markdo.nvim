return function(eq, buffer, notices)
  local api = vim.api
  local md = require('markdo')
  local function lines() return api.nvim_buf_get_lines(0, 0, -1, false) end
  local function pos() return api.nvim_win_get_cursor(0) end
  local source = {
    '- [ ] root', '  - [ ] parent', '    - plain', '      1) [ ] child',
    '         continuation', '         ```sh', '         # [ ] code', '         ```',
    '', '- [X] already checked', '', '# Later', '- [ ] next task',
  }
  buffer(source, 7)
  eq(vim.fn.exists(':MarkDoDoneNext'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoDoneNext)', 'n', false, true).buffer, 1)
  local cursor = pos()
  vim.cmd.MarkDoDoneNext()
  eq(pos(), { 13, 2 })
  eq(lines()[1], '- [x] root'); eq(lines()[2], '  - [x] parent')
  eq(lines()[4], '      1) [x] child')
  eq(lines()[7], source[7]); eq(lines()[10], source[10])
  eq(api.nvim_buf_get_mark(0, "'"), cursor)
  vim.cmd.undo(); eq(lines(), source) -- Child and both ancestors in one step.
  vim.cmd.redo(); eq(lines()[1], '- [x] root'); eq(lines()[4], '      1) [x] child')
  -- No following match: completion still succeeds, with the cursor preserved.
  buffer({ '- [ ] last', '  continuation' }, 2)
  cursor = pos()
  md.done_next(); eq(lines()[1], '- [x] last'); eq(pos(), cursor)
  eq(notices[#notices], 'Mark Do: No next unfinished task')
  vim.cmd.undo(); eq(lines()[1], '- [ ] last')
  -- Checked tasks advance without rewriting [X], recomputing parents or undo.
  local checked = { '- [ ] manual parent', '  - [X] child', '- [ ] next' }
  local buf = buffer(checked, 2)
  local tick, sequence = api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur
  md.done_next(); eq(pos(), { 3, 2 }); eq(lines(), checked)
  eq(api.nvim_buf_get_changedtick(buf), tick); eq(vim.fn.undotree().seq_cur, sequence)
  -- Direct completion of a parent still leaves its children untouched.
  buffer({ '- [ ] parent', '  - [ ] child' })
  md.done_next(); eq(pos(), { 2, 4 })
  eq(lines(), { '- [x] parent', '  - [ ] child' })
  -- The selected next task reflects unsaved text, and closed folds open.
  buffer({ '- [ ] current', '- [ ] skip', '- [x] reopened', '  body' })
  api.nvim_buf_set_text(0, 1, 3, 1, 4, { 'x' })
  api.nvim_buf_set_text(0, 2, 3, 2, 4, { ' ' })
  vim.wo.foldmethod = 'manual'; vim.cmd('3,4fold')
  api.nvim_win_set_cursor(0, { 1, 0 })
  md.done_next(); eq(pos(), { 3, 2 }); eq(vim.fn.foldclosed(3), -1)
  -- No task at the cursor means no completion and no navigation.
  for _, case in ipairs({
    { { '# Heading', '- [ ] next' }, 1 },
    { { '- [ ] before', '', '- [ ] next' }, 2 },
    { { '```markdown', '- [ ] code', '```', '- [ ] next' }, 2 },
  }) do
    buffer(case[1], case[2]); cursor = pos()
    md.done_next(); eq(pos(), cursor); eq(lines(), case[1])
    eq(notices[#notices], 'Mark Do: No task at cursor')
  end
  -- Missing parser: one actionable error and no partial navigation.
  buffer({ '- [ ] current', '- [ ] next' })
  local get_parser, before = vim.treesitter.get_parser, #notices
  vim.treesitter.get_parser = function() error('parser unavailable') end
  md.done_next(); eq(pos(), { 1, 0 }); eq(lines()[1], '- [ ] current')
  eq(#notices, before + 1)
  eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  vim.treesitter.get_parser = get_parser
  -- The ordinary Done action continues to preserve the cursor.
  cursor = pos(); md.done(); eq(pos(), cursor)
  vim.cmd.enew({ bang = true }); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoDoneNext'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoDoneNext)', 'n'), '')
end
