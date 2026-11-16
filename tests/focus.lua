return function(eq, buffer, notices)
  local a, md = vim.api, require('markdo')
  local function at(row, col) a.nvim_win_set_cursor(0, { row, col or 0 }) end
  local function closed(row) return vim.fn.foldclosed(row) end
  local function wait_closed(row, expected)
    vim.wait(1000, function() return closed(row) == expected end, 5)
    eq(closed(row), expected)
  end
  local source = {
    '# Runbook', '- [X] complete', '  - [x] child', '    ```sh', '    # [ ] code', '    ```', '',
    '- [x] manual parent', '  - [ ] open child', '  - plain', '    1) [X] done child',
    '       body', '', '- [ ] parent', '  - [x] completed child', '    body', '',
    '## Next', '- [ ] open', '- [x] last', '  body', '',
  }
  local buf = buffer(source, 9)
  eq(vim.fn.exists(':MarkDoFocusToggle'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoFocusToggle)', 'n', false, true).buffer, 1)
  vim.wo.foldmethod = 'manual'; vim.cmd('18,21fold'); vim.cmd('normal! zR'); at(9, 4)
  local tick, sequence, view = a.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur, vim.fn.winsaveview()
  local filename, alternate, viewoptions = a.nvim_buf_get_name(buf), vim.fn.bufnr('#'), vim.o.viewoptions
  local file_events = 0
  local group = a.nvim_create_augroup('MarkDoTestFocus', { clear = true })
  a.nvim_create_autocmd({ 'BufFilePre', 'BufFilePost', 'OptionSet' }, { group = group, pattern = '*',
    callback = function(ev) if ev.event ~= 'OptionSet' or ev.match == 'viewoptions' then file_events = file_events + 1 end end })
  vim.fn.setreg('/', 'search preserved')
  vim.cmd.MarkDoFocusToggle()
  eq(closed(2), 2); eq(vim.fn.foldclosedend(2), 6); eq(closed(7), -1)
  eq(closed(8), -1); eq(closed(9), -1) -- Checked parent with open child stays visible.
  eq(closed(11), 11); eq(closed(15), 15); eq(closed(19), -1); eq(closed(20), 20)
  eq(closed(18), -1) -- Existing folds must not hide headings/open work in Focus.
  eq(a.nvim_buf_get_lines(buf, 0, -1, false), source)
  eq(a.nvim_buf_get_changedtick(buf), tick); eq(vim.fn.undotree().seq_cur, sequence)
  eq(a.nvim_buf_get_name(buf), filename); eq(vim.fn.bufnr('#'), alternate)
  eq(vim.o.viewoptions, viewoptions); eq(file_events, 0); eq(vim.fn.getreg('/'), 'search preserved')
  vim.cmd.MarkDoFocusToggle()
  eq(closed(2), -1); eq(vim.fn.foldlevel(18), 1); eq(closed(18), -1)
  eq(vim.fn.winsaveview(), view)
  a.nvim_del_augroup_by_id(group)
  -- Exact restoration of adjacent and nested manual folds and their exceptions.
  buffer({ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' })
  vim.wo.foldmethod = 'manual'; vim.wo.foldminlines = 0
  vim.cmd('2,6fold'); vim.cmd('normal! zR'); vim.cmd('3,4fold')
  vim.cmd('7,8fold'); at(1)
  local function signature()
    local result = {}
    for row = 1, 8 do result[row] = { vim.fn.foldlevel(row), closed(row), vim.fn.foldclosedend(row) } end
    return result
  end
  local before = signature()
  md.toggle_focus(); md.toggle_focus(); eq(signature(), before)
  -- Closed outer folds retain an open inner exception when reopened later.
  at(3); vim.cmd('normal! zo'); at(2); vim.cmd('normal! zc'); at(1)
  md.toggle_focus(); md.toggle_focus(); eq(closed(2), 2)
  at(2); vim.cmd('normal! zo'); eq(closed(3), -1)
  at(3); vim.cmd('normal! zc'); at(1)
  -- Folds and cursor anchors follow inserted lines while Focus is active.
  at(5, 0); md.toggle_focus()
  a.nvim_buf_set_lines(0, 0, 0, false, { '# Inserted' })
  md.toggle_focus(); eq(vim.fn.foldlevel(3), 1); eq(closed(4), 4)
  eq(vim.fn.foldclosedend(4), 5); eq(a.nvim_win_get_cursor(0)[1], 6)
  -- Named buffers are not written while capturing fold state.
  buffer({ '- [x] done', '  body', '- [ ] open' })
  local name = vim.fn.tempname() .. '.md'
  a.nvim_buf_set_name(0, name)
  vim.wo.foldmethod = 'manual'; vim.cmd('1,2fold')
  md.toggle_focus(); md.toggle_focus()
  eq(a.nvim_buf_get_name(0), name); eq(vim.fn.filereadable(name), 0); eq(closed(1), 1)
  -- Computed fold options and closed exceptions are restored too.
  buffer({ 'top', 'a', 'b', 'c', 'bottom' })
  vim.wo.foldmethod = 'expr'; vim.wo.foldexpr = 'v:lnum >= 2 && v:lnum <= 4 ? 1 : 0'
  vim.wo.foldlevel = 3; vim.cmd('normal! zx'); at(2); vim.cmd('normal! zc'); at(1)
  eq(closed(2), 2)
  local options = {}
  for _, name in ipairs({ 'foldmethod', 'foldexpr', 'foldlevel', 'foldminlines', 'foldenable', 'foldtext' }) do options[name] = vim.wo[name] end
  md.toggle_focus(); md.toggle_focus()
  for name, value in pairs(options) do eq(vim.wo[name], value) end
  eq(closed(2), 2)
  -- Nonmodifiable scratch buffers and originally disabled folding work.
  buffer({ '- [x] complete', '  body', '- [ ] open' })
  vim.bo.buftype = 'nofile'; vim.bo.modifiable = false
  vim.wo.foldmethod = 'manual'; vim.cmd('1,2fold'); vim.wo.foldenable = false
  md.toggle_focus(); eq(closed(1), 1)
  md.toggle_focus(); eq(vim.bo.buftype, 'nofile'); eq(vim.wo.foldenable, false)
  vim.wo.foldenable = true; eq(vim.fn.foldlevel(1), 1)
  vim.bo.modifiable = true
  -- Real headings inside a complete task remain visible; code headings do not.
  buffer({ '- [x] task', '  body', '', '  ## Heading', '  - [x] child', '    ```', '    # code', '    ```' })
  md.toggle_focus(); eq(closed(1), 1); eq(closed(4), -1); eq(closed(5), 5); eq(closed(7), 5)
  md.toggle_focus()
  buffer({ '- [x] task', '  body', '', '  Heading', '  -------', '', '  - [x] child', '    body' })
  md.toggle_focus(); eq(closed(4), -1); eq(closed(5), -1); eq(closed(7), 7)
  md.toggle_focus()
  -- Changes, undo and reset refresh Focus without checking anything themselves.
  buffer({ '- [ ] parent', '  - [x] child', '    body', '  - [ ] other', '    body' }, 4)
  md.toggle_focus(); eq(closed(1), -1); eq(closed(2), 2)
  md.done(); wait_closed(1, 1)
  vim.cmd.undo(); wait_closed(1, -1); eq(closed(2), 2)
  a.nvim_buf_set_text(0, 0, 3, 0, 4, { 'x' }); wait_closed(1, -1)
  eq(a.nvim_buf_get_lines(0, 0, 1, false)[1], '- [x] parent')
  a.nvim_buf_set_text(0, 3, 5, 3, 6, { 'x' }); wait_closed(1, 1)
  md.reset('buffer'); wait_closed(1, -1); eq(closed(2), -1)
  md.toggle_focus()
  -- Deleting and undoing text while focused preserves snapshot anchors.
  buffer({ '- [x] done', '  body', '- [ ] open', '  body' })
  vim.wo.foldmethod = 'manual'; vim.cmd('3,4fold'); at(1)
  md.toggle_focus()
  vim.cmd('let &undolevels = &undolevels')
  a.nvim_buf_set_lines(0, 0, -1, false, {})
  wait_closed(1, -1)
  vim.cmd.undo(); wait_closed(1, 1)
  md.toggle_focus(); eq(closed(3), 3); eq(vim.fn.foldclosedend(3), 4)
  -- Restore a scrolled view, including a horizontal offset, after navigation.
  local long = {}
  for i = 1, 120 do long[i] = ('- [%s] task %d %s'):format(i < 60 and 'x' or ' ', i, string.rep('text ', 30)) end
  buffer(long, 90)
  vim.wo.wrap = false
  vim.fn.winrestview({ lnum = 90, col = 85, curswant = 85, topline = 85, leftcol = 60 })
  local scrolled = vim.fn.winsaveview()
  md.toggle_focus(); at(70); vim.cmd('normal! zt'); md.toggle_focus()
  eq(vim.fn.winsaveview(), scrolled)
  vim.wo.wrap = true
  -- Two views are independent; splitting a focused view starts neutral.
  local shared = buffer({ '- [x] done', '  body', '- [ ] open', '  body' })
  local first = a.nvim_get_current_win()
  vim.wo.foldmethod = 'indent'; vim.wo.foldlevel = 5
  md.toggle_focus(); vim.cmd.vsplit()
  local second = a.nvim_get_current_win()
  eq(vim.wo.foldmethod, 'indent'); eq(closed(1), -1)
  a.nvim_set_current_win(first); eq(closed(1), 1)
  a.nvim_set_current_win(second); md.toggle_focus(); eq(closed(1), 1)
  a.nvim_set_current_win(first); md.toggle_focus(); eq(vim.wo.foldmethod, 'indent')
  a.nvim_set_current_win(second); eq(closed(1), 1)
  -- A buffer change restores this window; returning does not re-enable Focus.
  vim.cmd.enew({ bang = true }); eq(vim.wo.foldmethod, 'indent')
  a.nvim_win_set_buf(second, shared); eq(vim.wo.foldmethod, 'indent'); eq(closed(1), -1)
  md.toggle_focus()
  local other = a.nvim_create_buf(true, false)
  a.nvim_win_set_buf(first, other)
  a.nvim_set_current_win(first)
  eq(a.nvim_win_call(second, function() return closed(1) end), 1)
  a.nvim_set_current_win(second); eq(closed(1), 1)
  a.nvim_win_set_buf(first, shared); a.nvim_buf_delete(other, { force = true })
  a.nvim_buf_set_text(shared, 0, 3, 0, 4, { 'X' }) -- Queue a redraw, then close.
  a.nvim_win_close(second, true)
  a.nvim_set_current_win(first)
  -- Filetype changes and parser errors are safe; background failures show work.
  md.toggle_focus(); vim.bo.filetype = 'text'; eq(vim.wo.foldmethod, 'indent')
  vim.bo.filetype = 'markdown'
  local parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('no parser') end
  md.toggle_focus(); eq(vim.wo.foldmethod, 'indent')
  eq(notices[#notices]:find('TSInstall markdown') ~= nil, true)
  vim.treesitter.get_parser = parser
  md.toggle_focus()
  local notice_count = #notices
  vim.treesitter.get_parser = function() error('no parser') end
  a.nvim_buf_set_text(shared, 0, 3, 0, 4, { 'X' }); wait_closed(1, -1); eq(#notices, notice_count)
  vim.treesitter.get_parser = parser
  a.nvim_buf_set_text(shared, 0, 3, 0, 4, { 'x' }); wait_closed(1, 1)
  md.toggle_focus()
  -- Save failure leaves the name, view options and folds untouched.
  local tempname = vim.fn.tempname
  vim.fn.tempname = function() return '/nonexistent-markdo-dir/view' end
  md.toggle_focus(); eq(vim.wo.foldmethod, 'indent')
  eq(notices[#notices]:find('Could not save folds', 1, true) ~= nil, true)
  vim.fn.tempname = tempname
  a.nvim_set_current_buf(a.nvim_create_buf(true, false)); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoFocusToggle'), 0)
  eq(vim.fn.maparg('<Plug>(MarkDoFocusToggle)', 'n'), '')
end
