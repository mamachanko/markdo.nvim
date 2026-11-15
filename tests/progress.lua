return function(eq, buffer, notices)
  local api = vim.api
  local md = require('markdo')
  local source = {
    '- [x] parent',
    '  - [X] child A',
    '  - plain',
    '    1. [ ] child B',
    '- [ ] separate',
    '', '```markdown', '- [ ] code', '```',
    '', '~~~markdown', '- [x] more code', '~~~',
  }
  local buf = buffer(source, 4)
  eq(vim.fn.exists(':MarkDoProgress'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoProgress)', 'n', false, true).buffer, 1)
  local tick, sequence, cursor = api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur, api.nvim_win_get_cursor(0)
  local notices_before = #notices
  eq(md.progress(), { completed = 1, total = 3, percent = 33 })
  eq(md.progress(0), { completed = 1, total = 3, percent = 33 })
  eq(#notices, notices_before) -- API queries never notify.
  vim.cmd.MarkDoProgress()
  eq(notices[#notices], 'Mark Do: 1/3 tasks complete (33%)')
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), source)
  eq(api.nvim_buf_get_changedtick(buf), tick)
  eq(vim.fn.undotree().seq_cur, sequence)
  eq(api.nvim_win_get_cursor(0), cursor)
  -- Manual parent edits do not affect leaf counts; unsaved child edits do.
  api.nvim_buf_set_text(buf, 0, 3, 0, 4, { ' ' })
  eq(md.progress().percent, 33)
  api.nvim_buf_set_text(buf, 3, 8, 3, 9, { 'x' })
  eq(md.progress(), { completed = 2, total = 3, percent = 67 })
  md.toggle() -- Reopen the leaf under the cursor; undo updates progress too.
  eq(md.progress().percent, 33)
  vim.cmd.undo(); eq(md.progress().percent, 67)
  -- An explicit other buffer works without changing the current buffer.
  buffer({ '- [X] finished' })
  eq(md.progress(), { completed = 1, total = 1, percent = 100 })
  eq(md.progress(buf), { completed = 2, total = 3, percent = 67 })
  local result = md.progress(buf); result.total = 1000
  eq(md.progress(buf).total, 3) -- Callers cannot corrupt the cache.
  -- Turning a leaf into a parent changes the denominator on the next query.
  buffer({ '- [x] parent', '  - [ ] leaf' })
  eq(md.progress(), { completed = 0, total = 1, percent = 0 })
  api.nvim_buf_set_lines(0, 2, 2, false, { '    - [x] grandchild' })
  eq(md.progress(), { completed = 1, total = 1, percent = 100 })
  buffer({ '- [ ] only plain children', '  - plain', '    continuation' })
  eq(md.progress(), { completed = 0, total = 1, percent = 0 })
  buffer({ '# Empty', '```', '- [ ] code', '```', '- plain' })
  eq(md.progress(), { completed = 0, total = 0 })
  vim.cmd.MarkDoProgress(); eq(notices[#notices], 'Mark Do: No tasks')
  buffer({})
  eq(md.progress(), { completed = 0, total = 0 })
  local eighths = { '- [x] one' }
  for i = 2, 8 do eighths[i] = '- [ ] item ' .. i end
  buffer(eighths)
  eq(md.progress(), { completed = 1, total = 8, percent = 13 })
  -- Repeated statusline redraws reuse the parse until source text changes.
  buffer({ '- [ ] cached' })
  local parse, calls = require('markdo.parse'), 0
  local read = parse.read
  parse.read = function(...) calls = calls + 1; return read(...) end
  md.progress(); md.progress(); eq(calls, 1)
  api.nvim_buf_set_text(0, 0, 3, 0, 4, { 'X' })
  eq(md.progress().percent, 100); eq(calls, 2)
  parse.read = read
  -- A non-Markdown statusline returns a quiet error, even with a cached value.
  vim.bo.filetype = 'text'
  notices_before = #notices
  local stats, err = md.progress()
  eq(stats, nil); eq(err, 'Not a Markdown buffer'); eq(#notices, notices_before)
  vim.cmd.enew({ bang = true }); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoProgress'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoProgress)', 'n'), '')
  stats, err = md.progress(-1); eq(stats, nil); eq(err, 'Buffer is not loaded')
  api.nvim_buf_delete(buf, { force = true, unload = true })
  stats, err = md.progress(buf); eq(stats, nil); eq(err, 'Buffer is not loaded')
  api.nvim_buf_delete(buf, { force = true })
  stats, err = md.progress(buf); eq(stats, nil); eq(err, 'Buffer is not loaded')
  -- Missing-parser errors stay quiet through the API and are shown by command.
  buffer({ '- [ ] task' })
  local get_parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('parser unavailable') end
  notices_before = #notices
  stats, err = md.progress(); eq(stats, nil)
  eq(err:find('TSInstall markdown') ~= nil, true); eq(#notices, notices_before)
  vim.cmd.MarkDoProgress(); eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  vim.treesitter.get_parser = get_parser
  eq(md.progress().percent, 0) -- Parser failures are not cached.
end
