return function(eq, buffer, notices)
  local api, md = vim.api, require('markdo')
  local function lines() return api.nvim_buf_get_lines(0, 0, -1, false) end
  local function at(row, col) api.nvim_win_set_cursor(0, { row, col or 0 }) end
  local source = {
    '- [X] root', '  - [x] selected', '    continuation', '    - plain',
    '      1) [X] nested', '         ~~~sh', '         # - [x] code', '         ~~~',
    '  - [X] untouched sibling', '- [x] separate',
  }
  buffer(source, 7)
  eq(vim.fn.exists(':MarkDoReset'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoReset)', 'n', false, true).buffer, 1)
  eq(vim.api.nvim_buf_get_commands(0, {}).MarkDoReset.nargs, '?')
  eq(vim.fn.getcompletion('MarkDoReset s', 'cmdline'), { 'section' })
  local cursor = api.nvim_win_get_cursor(0)
  vim.cmd.MarkDoReset()
  eq(api.nvim_win_get_cursor(0), cursor)
  eq(lines()[1], '- [ ] root'); eq(lines()[2], '  - [ ] selected')
  eq(lines()[5], '      1) [ ] nested')
  eq(lines()[7], source[7]); eq(lines()[9], source[9]); eq(lines()[10], source[10])
  vim.cmd.undo(); eq(lines(), source)
  -- Reset from a parent includes all checkbox descendants through plain items.
  at(3); vim.cmd('MarkDoReset task')
  eq(lines()[2], '  - [ ] selected'); eq(lines()[5], '      1) [ ] nested')
  eq(lines()[9], source[9]); eq(lines()[10], source[10])
  vim.cmd.undo(); eq(lines(), source)
  vim.cmd.redo(); eq(lines()[5], '      1) [ ] nested')
  -- Without changes, leave undo/modified state and a manual ancestor alone.
  buffer({ '- [x] manual parent', '  - [ ] open child', '- [x] other' }, 2)
  local before, tick, sequence, modified = lines(), api.nvim_buf_get_changedtick(0), vim.fn.undotree().seq_cur, vim.bo.modified
  md.reset(); eq(lines(), before); eq(api.nvim_buf_get_changedtick(0), tick)
  eq(vim.fn.undotree().seq_cur, sequence); eq(vim.bo.modified, modified)
  eq(notices[#notices], 'Mark Do: Tasks already open')
  -- Ordered lists, preamble, nested heading sections, and fenced fake headings.
  local outline = {
    '- [X] preamble', '', '# Main', '- [X] main', '', '## Child',
    '1. [x] child', '```markdown', '# Fake heading', '- [x] fake task', '```',
    '### Deep', '- [X] deep', '', '## Sibling', '- [x] sibling', '# Next', '- [X] next',
  }
  buffer(outline, 3)
  vim.cmd('MarkDoReset section')
  eq(lines()[1], outline[1]); eq(lines()[4], '- [ ] main'); eq(lines()[7], '1. [ ] child')
  eq(lines()[10], outline[10]); eq(lines()[13], '- [ ] deep'); eq(lines()[16], '- [ ] sibling')
  eq(lines()[18], outline[18]); vim.cmd.undo(); eq(lines(), outline)
  at(9); md.reset('section') -- In a fence: use the enclosing real heading.
  eq(lines()[4], outline[4]); eq(lines()[7], '1. [ ] child'); eq(lines()[13], '- [ ] deep')
  eq(lines()[16], outline[16]); vim.cmd.undo(); eq(lines(), outline)
  at(1); md.reset('section'); eq(lines()[1], '- [ ] preamble'); eq(lines()[4], outline[4])
  vim.cmd.undo(); eq(lines(), outline)
  at(18); vim.cmd('MarkDoReset buffer')
  for _, row in ipairs({ 1, 4, 7, 13, 16, 18 }) do eq(lines()[row]:find('[ ]', 1, true) ~= nil, true) end
  eq(lines()[10], outline[10]); vim.cmd.undo(); eq(lines(), outline)
  -- Setext headings and their underline belong to the same parsed section.
  local setext = { 'Main', '====', '', '- [x] main', '', 'Child', '-----', '', '- [X] child', '', 'Next', '====', '', '- [x] next' }
  buffer(setext, 7); md.reset('section')
  eq(lines()[4], setext[4]); eq(lines()[9], '- [ ] child'); eq(lines()[14], setext[14])
  vim.cmd.undo(); eq(lines(), setext)
  at(2); md.reset('section'); eq(lines()[4], '- [ ] main'); eq(lines()[9], '- [ ] child')
  eq(lines()[14], setext[14]); vim.cmd.undo(); eq(lines(), setext)
  -- Heading sections within a quoted task reopen its outside ancestor only.
  local quoted = { '> - [x] parent', '>', '>   ## Section', '>   - [X] child', '', '- [X] outside' }
  buffer(quoted, 3); md.reset('section')
  eq(lines()[1], '> - [ ] parent'); eq(lines()[4], '>   - [ ] child'); eq(lines()[6], quoted[6])
  vim.cmd.undo(); eq(lines(), quoted)
  -- A document without headings is its own preamble section.
  buffer({ '- [x] one', '', '- [X] two' }, 2); md.reset('section')
  eq(lines(), { '- [ ] one', '', '- [ ] two' })
  -- Bulk resets update progress/inline summaries; undo restores unsaved edits.
  buffer({ '- [x] parent', '  - [x] a', '  - [ ] b' })
  api.nvim_buf_set_text(0, 2, 5, 2, 6, { 'X' })
  before = lines()
  md.toggle_inline_progress(); md.reset('buffer')
  eq(md.progress().percent, 0)
  local ns = api.nvim_get_namespaces()['markdo.inline_progress']
  local function text()
    local marks = api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    return marks[1] and marks[1][4].virt_text[1][1]
  end
  eq(vim.wait(1000, function() return text() == '  0/2 · 0%' end, 5), true)
  vim.cmd.undo(); eq(lines(), before); eq(md.progress().percent, 100)
  eq(vim.wait(1000, function() return text() == '  2/2 · 100%' end, 5), true)
  md.toggle_inline_progress()
  -- Empty scopes, invalid input, blank sibling boundaries, and missing parsers.
  buffer({ '# Heading', '- [x] next' })
  cursor = api.nvim_win_get_cursor(0); before = lines()
  md.reset(); eq(lines(), before); eq(api.nvim_win_get_cursor(0), cursor)
  eq(notices[#notices], 'Mark Do: No task at cursor')
  md.reset('typo'); eq(lines(), before)
  eq(notices[#notices], 'Mark Do: Unknown reset scope; use task, section, or buffer')
  buffer({ '- [x] one', '', '- [x] two' }, 2); before = lines()
  md.reset(); eq(lines(), before); eq(notices[#notices], 'Mark Do: No task at cursor')
  buffer({ '# Empty', '```', '- [x] code', '```' })
  md.reset('section'); eq(notices[#notices], 'Mark Do: No tasks in this section')
  md.reset('buffer'); eq(notices[#notices], 'Mark Do: No tasks in this buffer')
  buffer({ '- [X] task' }); before = lines()
  local parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('missing parser') end
  md.reset('buffer'); eq(lines(), before)
  eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  vim.treesitter.get_parser = parser
  api.nvim_set_current_buf(api.nvim_create_buf(true, false)); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoReset'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoReset)', 'n'), '')
end
