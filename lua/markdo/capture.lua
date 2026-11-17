local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('markdo.capture')
local runs = {}
local limit = 1024 * 1024

local function discard(run)
  if not run then return end
  run.live = false
  if api.nvim_buf_is_valid(run.buf) then
    for _, id in ipairs({ run.anchor, run.captured }) do
      if id then pcall(api.nvim_buf_del_extmark, run.buf, ns, id) end
    end
  end
end
api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
  group = api.nvim_create_augroup('MarkDoCapture', { clear = true }),
  callback = function(ev) discard(runs[ev.buf]); runs[ev.buf] = nil end,
})

function M.start(data, fence)
  local first = fence.delimiters[1]:range()
  local last, col = fence.delimiters[2]:range()
  local marker = assert(data.lines[last + 1]:find('[`~]', col + 1))
  local run = { buf = data.buf, live = true, chunks = {}, bytes = 0,
    source = vim.list_slice(data.lines, first + 1, last + 1),
    prefix = data.lines[last + 1]:sub(1, marker - 1) }
  run.anchor = api.nvim_buf_set_extmark(data.buf, ns, first, 0, {
    end_row = last + 1, end_col = 0, right_gravity = true, end_right_gravity = false,
    invalidate = true, undo_restore = true,
  })
  discard(runs[data.buf])
  runs[data.buf] = run
  return run
end
-- A plain, line-oriented PTY transcript, independent of terminal width and
-- scrollback. Drop ANSI/OSC controls; CR and backspace overwrite the current
-- line. Full-screen cursor addressing is intentionally not replayed.
local function transcript(raw)
  local lines, line, col, i = {}, {}, 1, 1
  while i <= #raw do
    local byte = raw:byte(i)
    if byte == 27 then
      local kind = raw:sub(i + 1, i + 1)
      if kind == '[' then
        local last = raw:find('[@-~]', i + 2)
        if not last then break end
        local op, arg = raw:sub(last, last), tonumber(raw:sub(i + 2, last - 1)) or 0
        if op == 'K' then
          if arg == 2 then line = {}; for c = 1, col - 1 do line[c] = ' ' end
          elseif arg == 1 then for c = 1, col do line[c] = ' ' end
          elseif arg == 0 then for c = col, #line do line[c] = nil end end
        end
        i = last + 1
      elseif kind == ']' or kind == 'P' or kind == '^' or kind == '_' or kind == 'X' then
        local last = raw:find('\27\\', i + 2, true)
        local bell = kind == ']' and raw:find('\7', i + 2, true)
        if bell and (not last or bell < last) then i = bell + 1
        elseif last then i = last + 2 else break end
      elseif kind:match('[ -/]') then
        local last = raw:find('[0-~]', i + 2)
        i = last and last + 1 or #raw + 1
      else i = i + 2 end
    elseif byte == 13 then col = 1; i = i + 1
    elseif byte == 10 then lines[#lines + 1] = table.concat(line); line, col, i = {}, 1, i + 1
    elseif byte == 8 then col = math.max(1, col - 1); i = i + 1
    elseif byte == 9 then
      repeat line[col] = ' '; col = col + 1 until (col - 1) % 8 == 0
      i = i + 1
    elseif byte < 32 or byte == 127 then i = i + 1
    else
      local size = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
      line[col], col, i = raw:sub(i, i + size - 1), col + 1, i + size
    end
  end
  if #line > 0 then lines[#lines + 1] = table.concat(line) end
  return lines
end
local function finish(run)
  -- Job exit can arrive before the final PTY read. Wait for both events.
  if run.code ~= nil and run.eof then
    run.output = not run.overflow and transcript(table.concat(run.chunks)) or nil
    run.chunks, run.ready = nil, true
  end
end
function M.append(run, data)
  if not run or not run.live or run.ready then return end
  if #data == 1 and data[1] == '' then run.eof = true; finish(run); return end
  if run.overflow then return end
  local chunk = table.concat(data, '\n')
  run.bytes = run.bytes + #chunk
  if run.bytes > limit then run.chunks = {}; run.overflow = true; return end
  run.chunks[#run.chunks + 1] = chunk
end
function M.finish(run, code, stopped)
  if not run or not run.live then return end
  run.code, run.eof = code, run.eof or stopped
  finish(run)
end
local function position(buf, id)
  local mark = api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
  if #mark > 0 and not mark[3].invalid and mark[1] < mark[3].end_row then return mark[1], mark[3].end_row end
end
function M.insert(buf)
  local run = runs[buf]
  if not run then return nil, 'No run to capture in this buffer' end
  if run.code == nil then return nil, 'Run still active; capture after exit' end
  if not run.ready then return nil, 'Output still arriving; retry Capture' end
  if run.overflow then return nil, 'Output exceeds 1 MiB; capture unavailable' end
  if not api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= 'markdown' then return nil, 'Source buffer unavailable' end
  if not vim.bo[buf].modifiable then return nil, 'Source buffer is not modifiable' end
  local first, last = position(buf, run.anchor)
  if not first or not vim.deep_equal(api.nvim_buf_get_lines(buf, first, last, false), run.source) then
    return nil, 'Source fence changed; run it again'
  end
  -- Extmark invalidation on undo/redo differs between 0.11 and 0.12. The
  -- inserted bytes also identify a restored capture immediately below source.
  if run.captured and (position(buf, run.captured)
    or vim.deep_equal(api.nvim_buf_get_lines(buf, last, last + #run.addition, false), run.addition)) then
    return nil, 'Output already captured'
  end
  local data, err = require('markdo.parse').read(buf)
  if not data then return nil, err end
  local found = false
  for _, fence in ipairs(data.fences) do
    if fence.row == first and #fence.delimiters == 2 and fence.delimiters[2]:range() == last - 1 then found = true; break end
  end
  if not found then return nil, 'Source fence changed; run it again' end
  local size = 3
  for _, line in ipairs(run.output) do for ticks in line:gmatch('`+') do size = math.max(size, #ticks + 1) end end
  local ticks, prefix = string.rep('`', size), run.prefix
  local blank = prefix:gsub('%s+$', '')
  local addition = { blank, prefix .. ticks .. 'text', prefix .. 'exit ' .. run.code }
  if #run.output > 0 then
    addition[#addition + 1] = blank
    for _, line in ipairs(run.output) do addition[#addition + 1] = prefix .. line end
  end
  addition[#addition + 1] = prefix .. ticks
  local view = vim.fn.winsaveview()
  vim.cmd('let &undolevels = &undolevels')
  api.nvim_buf_set_lines(buf, last, last, false, addition)
  if view.lnum > last then view.lnum = view.lnum + #addition end
  if view.topline > last then view.topline = view.topline + #addition end
  vim.fn.winrestview(view)
  if run.captured then api.nvim_buf_del_extmark(buf, ns, run.captured) end
  run.captured = api.nvim_buf_set_extmark(buf, ns, last, 0, {
    end_row = last + #addition, end_col = 0, invalidate = true, undo_restore = true,
    right_gravity = false, end_right_gravity = true,
  })
  run.addition = addition
  return true
end
return M
