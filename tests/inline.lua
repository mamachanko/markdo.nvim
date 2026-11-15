return function(eq, buffer, notices)
  local api = vim.api
  local md = require('markdo')
  local ns = api.nvim_create_namespace('markdo.inline_progress')
  local function marks(buf) return api.nvim_buf_get_extmarks(buf or 0, ns, 0, -1, { details = true }) end
  local function summaries(buf)
    local result = {}
    for _, mark in ipairs(marks(buf)) do result[mark[2] + 1] = mark[4].virt_text[1][1] end
    return result
  end
  local function expect(buf, expected)
    vim.wait(1000, function() return vim.deep_equal(summaries(buf), expected) end, 5)
    eq(summaries(buf), expected)
  end
  local function drain()
    local done = false
    vim.schedule(function() done = true end)
    assert(vim.wait(1000, function() return done end, 5))
  end
  local source = {
    '- [ ] root', '  - [x] group', '    1. [X] A', '    2. [ ] B',
    '  - plain', '    - [ ] C', '- [ ] standalone',
    '', '```markdown', '- [ ] code parent', '  - [ ] code child', '```',
  }
  local buf = buffer(source, 4)
  eq(vim.fn.exists(':MarkDoProgressToggle'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoProgressToggle)', 'n', false, true).buffer, 1)
  eq(marks(buf), {}) -- Default remains off.
  local tick, sequence, cursor = api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur, api.nvim_win_get_cursor(0)
  local other_ns = api.nvim_create_namespace('markdo.test.other')
  api.nvim_buf_set_extmark(buf, other_ns, 0, 0, { virt_text = { { 'other plugin' } } })
  vim.cmd.MarkDoProgressToggle()
  expect(buf, { [1] = '  1/3 · 33%', [2] = '  1/2 · 50%' })
  eq(notices[#notices], 'Mark Do: Inline progress enabled')
  for _, mark in ipairs(marks(buf)) do
    eq(mark[4].virt_text[1][2], 'Comment'); eq(mark[4].virt_text_pos, 'eol')
  end
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), source)
  eq(api.nvim_buf_get_changedtick(buf), tick)
  eq(vim.fn.undotree().seq_cur, sequence)
  eq(api.nvim_win_get_cursor(0), cursor)
  -- Command changes, including roll-up, refresh the decorations.
  md.done()
  expect(buf, { [1] = '  2/3 · 67%', [2] = '  2/2 · 100%' })
  vim.cmd.undo()
  expect(buf, { [1] = '  1/3 · 33%', [2] = '  1/2 · 50%' })
  vim.cmd.redo()
  expect(buf, { [1] = '  2/3 · 67%', [2] = '  2/2 · 100%' })
  -- Manual edits only update numbers, even with a manually checked parent.
  api.nvim_buf_set_text(buf, 0, 3, 0, 4, { 'x' })
  api.nvim_buf_set_text(buf, 2, 8, 2, 9, { ' ' })
  expect(buf, { [1] = '  1/3 · 33%', [2] = '  1/2 · 50%' })
  eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], '- [x] root')
  -- Structural edits move rows and remove parents that no longer have children.
  api.nvim_buf_set_lines(buf, 0, 0, false, { '# Heading', '' })
  expect(buf, { [3] = '  1/3 · 33%', [4] = '  1/2 · 50%' })
  api.nvim_buf_set_lines(buf, 4, 6, false, {})
  expect(buf, { [3] = '  1/2 · 50%' })
  -- Other buffers are off and can be enabled independently.
  local second = buffer({ '- [ ] parent', '  - [ ] child' })
  eq(marks(second), {})
  vim.cmd.MarkDoProgressToggle(); expect(second, { [1] = '  0/1 · 0%' })
  api.nvim_buf_set_text(buf, 5, 7, 5, 8, { 'x' })
  expect(buf, { [3] = '  2/2 · 100%' })
  expect(second, { [1] = '  0/1 · 0%' })
  -- Disable during a queued update: the callback must not restore annotations.
  api.nvim_buf_set_text(second, 1, 5, 1, 6, { 'x' })
  vim.cmd.MarkDoProgressToggle(); drain(); eq(marks(second), {})
  eq(notices[#notices], 'Mark Do: Inline progress disabled')
  vim.cmd.MarkDoProgressToggle(); expect(second, { [1] = '  1/1 · 100%' })
  vim.bo.filetype = 'text'; drain(); eq(marks(second), {})
  vim.bo.filetype = 'markdown'; drain(); eq(marks(second), {})
  vim.cmd.MarkDoProgressToggle(); expect(second, { [1] = '  1/1 · 100%' })
  -- Clear only our namespace; another plugin's decorations survive.
  api.nvim_set_current_buf(buf); vim.cmd.MarkDoProgressToggle()
  eq(marks(buf), {})
  eq(#api.nvim_buf_get_extmarks(buf, other_ns, 0, -1, {}), 1)
  -- A nonmodifiable checklist can still display progress.
  vim.bo.modifiable = false
  vim.cmd.MarkDoProgressToggle(); expect(buf, { [3] = '  2/2 · 100%' })
  vim.cmd.MarkDoProgressToggle(); eq(marks(buf), {})
  vim.bo.modifiable = true
  -- No annotations for leaves, plain lists or fenced checkbox text.
  local empty = buffer({ '- [ ] standalone', '- plain', '```', '- [ ] fake', '  - [ ] nested fake', '```' })
  vim.cmd.MarkDoProgressToggle(); eq(marks(empty), {})
  api.nvim_buf_set_lines(empty, 1, 1, false, { '  - [ ] new child' })
  expect(empty, { [1] = '  0/1 · 0%' })
  api.nvim_buf_set_lines(empty, 0, -1, false, {})
  expect(empty, {})
  -- A missing parser prevents enabling and shows the actionable dependency.
  local failed = buffer({ '- [ ] parent', '  - [ ] child' })
  local get_parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('parser unavailable') end
  vim.cmd.MarkDoProgressToggle(); eq(marks(failed), {})
  eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  vim.treesitter.get_parser = get_parser
  vim.cmd.MarkDoProgressToggle(); expect(failed, { [1] = '  0/1 · 0%' })
  -- Background parser errors clear stale output without repeated notifications.
  local before = #notices
  vim.treesitter.get_parser = function() error('parser unavailable') end
  api.nvim_buf_set_text(failed, 1, 5, 1, 6, { 'x' })
  expect(failed, {}); eq(#notices, before)
  vim.treesitter.get_parser = get_parser
  api.nvim_buf_set_text(failed, 1, 5, 1, 6, { ' ' })
  expect(failed, { [1] = '  0/1 · 0%' })
  -- Deleting/unloading with callbacks pending is safe and drops opt-in state.
  api.nvim_buf_set_text(failed, 1, 5, 1, 6, { 'x' })
  api.nvim_buf_delete(failed, { force = true }); drain()
  api.nvim_buf_set_text(second, 1, 5, 1, 6, { ' ' })
  api.nvim_buf_delete(second, { force = true, unload = true }); drain()
  vim.fn.bufload(second)
  eq(marks(second), {})
  api.nvim_buf_delete(second, { force = true })
  api.nvim_set_current_buf(api.nvim_create_buf(true, false)); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoProgressToggle'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoProgressToggle)', 'n'), '')
  api.nvim_buf_delete(buf, { force = true })
  api.nvim_buf_delete(empty, { force = true })
end
