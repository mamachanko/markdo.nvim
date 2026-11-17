return function(eq, buffer, notices)
  local a, md = vim.api, require('markdo')
  local function lines(buf) return a.nvim_buf_get_lines(buf or 0, 0, -1, false) end
  local function at(row) a.nvim_win_set_cursor(0, { row, 0 }) end
  local function key(buf, name)
    for _, map in ipairs(a.nvim_buf_get_keymap(buf, 'n')) do if map.lhs == name then map.callback(); return end end
    error('Missing terminal key ' .. name)
  end
  local function wait_exit(term)
    assert(vim.wait(5000, function() return vim.b[term].markdo_exit_code ~= nil end, 5), 'run did not exit')
  end
  local function run()
    md.run()
    local term, win = a.nvim_get_current_buf(), a.nvim_get_current_win()
    wait_exit(term); vim.cmd.stopinsert(); key(term, 'q')
    assert(not a.nvim_win_is_valid(win))
    return term
  end
  local function refuses(text)
    local before, sequence = lines(), vim.fn.undotree().seq_cur
    md.capture()
    eq(notices[#notices]:find(text, 1, true) ~= nil, true)
    eq(lines(), before); eq(vim.fn.undotree().seq_cur, sequence)
  end
  buffer({ '- [ ] nothing run' })
  eq(vim.fn.exists(':MarkDoCapture'), 2)
  eq(vim.fn.maparg('<Plug>(MarkDoCapture)', 'n', false, true).buffer, 1)
  refuses('No run')
  local source = {
    '# Runbook', '- [ ] parent', '  1. [ ] child', '     ```sh',
    [[     value=hello; printf '\033[32m%s\033[0m\n\n' "$value"]],
    [[     printf 'errline\n' >&2]], [[     printf '````\n- [ ] code\n  indented\n']],
    [[     printf 'working\rfinished\033[K\nabc\bX\n']],
    [[     printf '\033]0;hidden title\007visible\033]8;;https://example.com\033\\link\033]8;;\033\\\n']],
    "     printf '%s\\n' '" .. string.rep('long', 60) .. "'", '     exit 7', '     ```',
    '', '- [ ] sibling',
  }
  local buf = buffer(source, 3)
  run()
  -- Results survive closing/deleting the terminal. Unrelated edits track the fence.
  a.nvim_buf_set_lines(buf, 0, 0, false, { 'Preamble', '' })
  at(5)
  local before, cursor = lines(), a.nvim_win_get_cursor(0)
  vim.fn.setreg('a', 'preserved'); vim.fn.setreg('"', 'preserved too')
  vim.cmd.MarkDoCapture()
  eq(a.nvim_win_get_cursor(0), cursor)
  eq(vim.fn.getreg('a'), 'preserved'); eq(vim.fn.getreg('"'), 'preserved too')
  local data = assert(require('markdo.parse').read(buf))
  eq(#data.tasks, 3); eq(#data.fences, 2); eq(data.fences[2].owner, data.tasks[2])
  eq(data.fences[2].lang, 'text')
  eq(require('markdo.parse').body(data, data.fences[2]), table.concat({
    'exit 7', '', 'hello', '', 'errline', '````', '- [ ] code', '  indented', 'finished', 'abX', 'visiblelink', string.rep('long', 60),
  }, '\n'))
  eq(lines()[16], '     `````text')
  eq(lines()[4], '- [ ] parent'); eq(lines()[5], '  1. [ ] child')
  refuses('already captured')
  vim.cmd.undo(); eq(lines(), before)
  vim.cmd.redo(); refuses('already captured')
  vim.cmd.undo(); md.capture(); eq(#lines() > #before, true)
  vim.cmd.undo(); eq(lines(), before)
  -- Changes inside the source refuse capture; undoing them restores the identity.
  vim.cmd('let &undolevels = &undolevels')
  a.nvim_buf_set_lines(buf, 6, 7, false, { '     echo changed' })
  refuses('Source fence changed')
  vim.cmd.undo()
  vim.bo.modifiable = false; refuses('not modifiable'); vim.bo.modifiable = true
  local parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function() error('missing') end
  refuses('TSInstall markdown'); vim.treesitter.get_parser = parser
  a.nvim_buf_set_lines(buf, 5, 14, false, {})
  refuses('Source fence changed')
  -- Container semantics: ordered task and blockquote, tilde source fence.
  buffer({ '> 1) [ ] task', '>    ~~~sh', [[>    printf 'one\n\n  two\n\n']], '>    ~~~', '', '# Next' }, 1)
  run(); at(6); local at_heading = a.nvim_win_get_cursor(0)
  md.capture()
  data = assert(require('markdo.parse').read(0))
  eq(#data.tasks, 1); eq(#data.fences, 2); eq(data.fences[2].owner, data.tasks[1])
  eq(require('markdo.parse').body(data, data.fences[2]), 'exit 0\n\none\n\n  two\n')
  eq(a.nvim_get_current_line(), '# Next')
  eq(a.nvim_win_get_cursor(0)[1] > at_heading[1], true)
  -- A new run replaces the previous result, without silently replacing captures.
  at(2); run(); md.capture(); data = assert(require('markdo.parse').read(0))
  eq(#data.fences, 3)
  -- Empty output still records the status, without terminal padding/exit messages.
  buffer({ '```sh', 'exit 0', '```' }); run(); md.capture()
  eq(lines(), { '```sh', 'exit 0', '```', '', '```text', 'exit 0', '```' })
  vim.cmd.undo()
  local jobstart = vim.fn.jobstart
  vim.fn.jobstart = function() return 0 end
  at(1); md.run(); vim.fn.jobstart = jobstart
  md.capture(); eq(lines()[6], 'exit 0') -- Failed starts keep the previous result.
  -- An unchanged fence inside a newly enclosing code block is no longer source.
  buffer({ '```sh', 'echo context', '```' }); run()
  a.nvim_buf_set_lines(0, 0, 0, false, { '````' })
  a.nvim_buf_set_lines(0, -1, -1, false, { '````' })
  refuses('Source fence changed')
  -- Capture while active is a no-op; stopped jobs can be captured after exit.
  local running = buffer({ '- [ ] run', '  ```sh', '  echo started; sleep 30', '  ```' })
  local sourcewin = a.nvim_get_current_win()
  md.run(); local term, float = a.nvim_get_current_buf(), a.nvim_get_current_win()
  assert(vim.wait(2000, function() return table.concat(lines(term), '\n'):find('started', 1, true) end, 5))
  a.nvim_set_current_win(sourcewin); refuses('still active')
  buffer({ '# Other buffer' }); refuses('No run')
  a.nvim_set_current_win(float); key(term, 'x'); wait_exit(term); key(term, 'q')
  a.nvim_set_current_buf(running); md.capture()
  eq(#lines() > 4, true); eq(lines()[1], '- [ ] run')
  data = assert(require('markdo.parse').read(0))
  eq(require('markdo.parse').body(data, data.fences[2]):find('started', 1, true) ~= nil, true)
  -- Exit before EOF, split control sequences, tabs, Unicode and erased lines.
  buffer({ '```sh', 'echo example', '```' })
  data = assert(require('markdo.parse').read(a.nvim_get_current_buf()))
  local capture = require('markdo.capture')
  local pending = capture.start(data, data.fences[1])
  capture.append(pending, { 'one\27[3' }); capture.finish(pending, 9)
  refuses('Output still arriving')
  capture.append(pending, { '1mtwo\27[0m\r', 'a\té\bX\r', 'hello\27[2Kthere\r', '' })
  capture.append(pending, { '' }); md.capture()
  data = assert(require('markdo.parse').read(0))
  eq(require('markdo.parse').body(data, data.fences[2]), 'exit 9\n\nonetwo\na       X\n     there')
  -- A bounded transcript cannot silently save incomplete large output.
  buffer({ '```sh', [[head -c 2097152 /dev/zero | tr '\000' x]], '```' }); run()
  refuses('exceeds 1 MiB')
  -- Unloading the source discards its result and extmarks.
  local unload = buffer({ '```sh', 'echo gone', '```' }); run()
  vim.bo.bufhidden = 'unload'; buffer({ '# Elsewhere' })
  a.nvim_set_current_buf(unload); vim.bo.filetype = 'markdown'; refuses('No run')
  vim.cmd.enew({ bang = true }); vim.bo.filetype = 'text'
  eq(vim.fn.exists(':MarkDoCapture'), 0)
end
