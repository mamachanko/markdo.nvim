return function(eq, buffer, notices, copied)
  local api, md, parse = vim.api, require('markdo'), require('markdo.parse')
  local source = vim.fn.readfile('tests/fixtures/details.md')
  local buf = buffer(source, 4)
  local data = assert(parse.read(buf))
  eq(#data.tasks, 3); eq(#data.fences, 1); eq(data.headings, { 0 })
  local fence, child = data.fences[1], data.tasks[2]
  eq(fence.owner, child); eq(child.parent, data.tasks[1])
  eq(data:task_at(3), child); eq(data:task_at(5), child); eq(data:task_at(23), child)
  local expected = {}
  for i = 10, 21 do expected[#expected + 1] = source[i]:sub(5) end
  eq(parse.body(data, fence), table.concat(expected, '\n'))
  for row = 8, 21 do
    local selected
    parse.select(data, row, function(value) selected = value end)
    eq(selected, fence) -- Include both delimiters and apparent nested Markdown.
  end
  -- Copy from the task, HTML wrapper, opening/body/closing lines, and closing tag.
  vim.bo.modified = false
  local tick, sequence = api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur
  for _, row in ipairs({ 4, 6, 7, 9, 10, 17, 22, 24 }) do
    api.nvim_win_set_cursor(0, { row, 0 }); local pos = api.nvim_win_get_cursor(0)
    md.copy(); eq(copied(), { expected, 'v' }); eq(api.nvim_win_get_cursor(0), pos)
  end
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), source)
  eq(api.nvim_buf_get_changedtick(buf), tick); eq(vim.fn.undotree().seq_cur, sequence); eq(vim.bo.modified, false)
  local sourcewin = api.nvim_get_current_win()
  api.nvim_win_set_cursor(0, { 4, 0 }); md.run()
  eq(api.nvim_get_current_win(), sourcewin)
  eq(notices[#notices], 'Mark Do: Unsupported or unlabelled shell fence')
  api.nvim_win_set_cursor(0, { 3, 0 }); md.copy()
  eq(notices[#notices], 'Mark Do: No fence in this scope'); eq(copied(), { expected, 'v' })
  -- Ownership recovery is shared by navigation and completion; code remains opaque.
  md.setup({ navigation = { copy_on_jump = true } })
  api.nvim_win_set_cursor(0, { 1, 0 }); md.next()
  eq(api.nvim_win_get_cursor(0)[1], 4); eq(copied(), { expected, 'v' })
  md.next(); eq(api.nvim_win_get_cursor(0)[1], 26); eq(copied(), { expected, 'v' })
  md.prev(); eq(api.nvim_win_get_cursor(0)[1], 4); md.setup()
  api.nvim_win_set_cursor(0, { 17, 0 })
  md.done(); eq(api.nvim_buf_get_lines(buf, 3, 4, false)[1], '  - [x] Create PR')
  eq(api.nvim_buf_get_lines(buf, 16, 17, false)[1], source[17])
  api.nvim_win_set_cursor(0, { 26, 0 }); md.done()
  eq(api.nvim_buf_get_lines(buf, 2, 3, false)[1], '- [x] Release notes')
  vim.cmd.undo(); eq(api.nvim_buf_get_lines(buf, 2, 3, false)[1], '- [ ] Release notes')
  eq(api.nvim_buf_get_lines(buf, 3, 4, false)[1], '  - [x] Create PR')
  vim.cmd.undo(); eq(api.nvim_buf_get_lines(buf, 0, -1, false), source)
  -- Recovered string-parser nodes survive an asynchronous picker; edits cancel.
  local select, pending = vim.ui.select
  local multiple = vim.deepcopy(source)
  table.insert(multiple, 23, '    ```text')
  table.insert(multiple, 24, '    second fence')
  table.insert(multiple, 25, '    ```')
  vim.ui.select = function(items, opts, callback)
    pending = { items = items, callback = callback }
    eq(#items, 2); eq(opts.format_item(items[1]):find('markdown', 1, true) ~= nil, true)
  end
  buffer(multiple, 4); md.copy(); collectgarbage('collect')
  pending.callback(pending.items[2]); eq(copied(), { { 'second fence' }, 'v' })
  md.copy(); api.nvim_buf_set_lines(0, 11, 12, false, { '    edited while choosing' })
  pending.callback(pending.items[1]); eq(notices[#notices]:find('retry', 1, true) ~= nil, true)
  eq(copied(), { { 'second fence' }, 'v' }); vim.ui.select = select
  -- Ordered tasks, quoted containers, uppercase tags/attributes, and tilde fences.
  local shell = { '1. [ ] parent', '   - [ ] child', '', '     <DETAILS open>',
    '     <SUMMARY class="prompt">Script</SUMMARY>', '', '     ~~~sh',
    '     value=wrapped', [[     printf '%s\n' "$value"]], [[     printf 'errline\n' >&2]],
    '     exit 9', '     ~~~', '', '     </DETAILS>' }
  buf = buffer(shell, 2)
  data = assert(parse.read(buf)); eq(#data.tasks, 2); eq(data.fences[1].owner, data.tasks[2])
  md.run(); local term, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 5))
  eq(vim.b[term].markdo_exit_code, 9); vim.cmd.stopinsert()
  for _, map in ipairs(api.nvim_buf_get_keymap(term, 'n')) do if map.lhs == 'q' then map.callback(); break end end
  eq(api.nvim_win_is_valid(win), false)
  md.capture(); data = assert(parse.read(buf))
  eq(#data.tasks, 2); eq(#data.fences, 2); eq(data.fences[2].owner, data.tasks[2])
  eq(parse.body(data, data.fences[2]), 'exit 9\n\nwrapped\nerrline')
  vim.cmd.undo(); eq(api.nvim_buf_get_lines(buf, 0, -1, false), shell)
  local quoted = {}
  for _, line in ipairs(shell) do quoted[#quoted + 1] = '> ' .. line end
  buffer(quoted, 2); md.copy()
  eq(copied(), { { 'value=wrapped', [[printf '%s\n' "$value"]], [[printf 'errline\n' >&2]], 'exit 9' }, 'v' })
  for _, delimiter in ipairs({ '```', '````', '~~~~' }) do
    buffer({ '> 1. [ ] parent', '>    - [ ] child', '>', '>      <details open>',
      '>      <summary>Prompt</summary>', '>', '>      ' .. delimiter .. 'markdown',
      '>      # mission', '>', '>      - [ ] code', '>      ' .. delimiter, '>      </details>' }, 2)
    md.copy(); eq(copied(), { { '# mission', '', '- [ ] code' }, 'v' })
    data = assert(parse.read(api.nvim_get_current_buf()))
    eq(#data.tasks, 2); eq(data.fences[1].owner, data.tasks[2])
  end
  -- A separate, dedented HTML block must still end the preceding list. Its
  -- literal checkbox remains HTML even while another wrapper is recovered.
  local separate = vim.deepcopy(source)
  vim.list_extend(separate, { '', '- [ ] unrelated', '<details>', '<summary>HTML</summary>',
    '- [ ] literal HTML', '', '  ```text', '  outside the list', '  ```', '', '</details>' })
  buffer(separate)
  data = assert(parse.read(api.nvim_get_current_buf()))
  eq(#data.tasks, 4); eq(#data.fences, 2); eq(data.fences[2].owner, nil)
  for _, task in ipairs(data.tasks) do eq(task.row == 30, false) end
  -- Do not manufacture fences hidden in an HTML block or indented code.
  for _, invalid in ipairs({
    { '- [ ] task', '', '  <details>', '  <summary>Prompt</summary>', '  ```markdown',
      '  # mission', '', '  text', '  ```', '  </details>' },
    { '- [ ] task', '', '      ```markdown', '      # mission', '      ```' },
  }) do
    local before = copied(); buffer(invalid); md.copy()
    eq(notices[#notices]:find('No fence', 1, true) ~= nil or notices[#notices]:find('Incomplete', 1, true) ~= nil, true)
    eq(copied(), before)
    data = assert(parse.read(api.nvim_get_current_buf()))
    for _, value in ipairs(data.fences) do eq(value.lang == 'markdown' and #value.delimiters == 2, false) end
  end
  -- Missing closing fences stay incomplete, rather than using an HTML close tag.
  buffer({ '- [ ] task', '', '  <details>', '  <summary>Prompt</summary>', '',
    '  ```markdown', '', '  ```', '', '  </details>' })
  md.copy(); eq(notices[#notices], 'Mark Do: Empty fence')
  buffer({ '- [ ] task', '', '  <details>', '  <summary>Prompt</summary>', '',
    '  ```markdown', '  body', '  </details>' })
  md.copy(); eq(notices[#notices], 'Mark Do: Incomplete fence')
  -- If recovery is unavailable, retain the original parse without changing source.
  local string_parser = vim.treesitter.get_string_parser
  buffer(source, 4)
  vim.treesitter.get_string_parser = function() error('cannot create recovery parser') end
  eq(pcall(parse.read, api.nvim_get_current_buf()), true)
  vim.treesitter.get_string_parser = function() return { parse = function() return nil end } end
  eq(pcall(parse.read, api.nvim_get_current_buf()), true)
  vim.treesitter.get_string_parser = string_parser
  eq(api.nvim_buf_get_lines(0, 0, -1, false), source)
end
