local M = {}
local api = vim.api
local snapshots = require('markdo.folds')
local states, listeners, pending = {}, {}, {}
local text_option = "v:lua.require'markdo.focus'.text()"
function M.text() return vim.fn.foldtext() end

local function ranges(data)
  local complete = {}
  for _, task in ipairs(data.tasks) do complete[task] = task.checked end
  for i = #data.tasks, 1, -1 do
    local task = data.tasks[i]
    if task.parent then complete[task.parent] = complete[task.parent] and complete[task] end
  end
  local result = {}
  local function add(first, last)
    while first <= last and data.lines[first + 1]:match('^%s*$') do first = first + 1 end
    while last >= first and data.lines[last + 1]:match('^%s*$') do last = last - 1 end
    if first <= last then result[#result + 1] = { first + 1, last + 1 } end
  end
  for _, task in ipairs(data.tasks) do
    if complete[task] and not (task.parent and complete[task.parent]) then
      local first, _, last, col = task.node:range()
      if col == 0 then last = last - 1 end
      while last > first and data.lines[last + 1]:match('^%s*$') do last = last - 1 end
      -- Keep actual headings visible even when they occur inside a task.
      for _, heading in ipairs(data.heading_ranges) do
        if heading.first >= first and heading.first <= last then
          if first < heading.first then add(first, heading.first - 1) end
          first = heading.last + 1
        end
      end
      add(first, last)
    end
  end
  return result
end
local function render(win, folds, view)
  api.nvim_win_call(win, function()
    local current = view or vim.fn.winsaveview()
    vim.wo.foldmethod, vim.wo.foldtext = 'manual', text_option
    vim.wo.foldenable, vim.wo.foldminlines, vim.wo.foldlevel, vim.wo.foldnestmax = true, 0, 0, 20
    vim.cmd('silent! normal! zE')
    for _, fold in ipairs(folds) do vim.cmd(('silent keepjumps %d,%dfold'):format(fold[1], fold[2])) end
    vim.fn.winrestview(current)
  end)
end
local function stop(win)
  local state = states[win]
  if not state then return true end
  states[win] = nil
  local ok, err = pcall(snapshots.restore, win, state.snapshot)
  snapshots.discard(state.snapshot)
  if not ok then return nil, 'Could not restore folds: ' .. tostring(err) end
  return true
end
local function refresh(buf)
  local active = false
  for _, state in pairs(states) do if state.buf == buf and not state.paused then active = true; break end end
  if not active then return end
  local data = require('markdo.parse').read(buf)
  local folds = data and ranges(data) or {}
  for win, state in pairs(states) do
    if state.buf == buf and not state.paused and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      render(win, folds)
    end
  end
end
local function queue(buf)
  local active = false
  for _, state in pairs(states) do if state.buf == buf and not state.paused then active = true; break end end
  if not active or pending[buf] then return end
  pending[buf] = true
  vim.schedule(function()
    pending[buf] = nil
    if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then refresh(buf) end
  end)
end
local function settle()
  for win, state in pairs(states) do
    if state.paused then
      if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= state.buf then
        states[win] = nil
        snapshots.discard(state.snapshot)
      else
        state.paused = false
        local data = require('markdo.parse').read(state.buf)
        render(win, data and ranges(data) or {}, state.focus_view)
      end
    end
  end
end
api.nvim_create_autocmd('BufLeave', {
  group = api.nvim_create_augroup('MarkDoFocus', { clear = true }),
  callback = function(ev)
    local win = api.nvim_get_current_win()
    local state = states[win]
    if state and state.buf == ev.buf and not state.paused then
      -- Restore before a possible buffer switch. If only the active window
      -- changes, BufEnter resumes Focus in the original window.
      state.focus_view = vim.fn.winsaveview()
      state.paused = true
      snapshots.restore(win, state.snapshot)
      vim.schedule(settle)
    end
  end,
})
api.nvim_create_autocmd('BufEnter', { group = 'MarkDoFocus', callback = settle })
api.nvim_create_autocmd('WinNew', { group = 'MarkDoFocus', callback = function()
  local win = api.nvim_get_current_win()
  local source = states[vim.fn.win_getid(vim.fn.winnr('#'))]
  if source and api.nvim_win_get_buf(win) == source.buf and vim.wo.foldtext == text_option then
    -- Splits copy window fold options. New windows start with the original
    -- user's folds instead of inheriting an untracked Focus overlay.
    snapshots.restore(win, source.snapshot, vim.fn.winsaveview())
  end
end })
api.nvim_create_autocmd('WinClosed', { group = 'MarkDoFocus', callback = function(ev)
  local win = tonumber(ev.match)
  local state = states[win]
  if state then states[win] = nil; snapshots.discard(state.snapshot) end
end })
api.nvim_create_autocmd({ 'FileType', 'BufUnload', 'BufWipeout' }, { group = 'MarkDoFocus', callback = function(ev)
  if ev.event == 'FileType' and vim.bo[ev.buf].filetype == 'markdown' then return end
  for win, state in pairs(states) do if state.buf == ev.buf then stop(win) end end
  if ev.event ~= 'FileType' then listeners[ev.buf], pending[ev.buf] = nil, nil end
end })
function M.toggle()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  if states[win] then
    local ok, err = stop(win)
    if not ok then return nil, err end
    return false
  end
  if vim.bo[buf].filetype ~= 'markdown' then return nil, 'Not a Markdown buffer' end
  if not vim.tbl_contains({ '', 'nofile', 'nowrite', 'acwrite' }, vim.bo[buf].buftype) then
    return nil, 'Focus requires a normal or scratch Markdown buffer'
  end
  local data, err = require('markdo.parse').read(buf)
  if not data then return nil, err end
  local snapshot
  snapshot, err = snapshots.capture(win)
  if not snapshot then return nil, err end
  local state = { buf = buf, snapshot = snapshot }
  if not listeners[buf] then
    local attached = api.nvim_buf_attach(buf, false, {
      on_lines = function() queue(buf) end,
      on_reload = function() queue(buf) end,
      on_detach = function() listeners[buf], pending[buf] = nil, nil end,
    })
    if not attached then snapshots.discard(snapshot); return nil, 'Could not watch buffer' end
    listeners[buf] = true
  end
  states[win] = state
  render(win, ranges(data))
  return true
end
return M
