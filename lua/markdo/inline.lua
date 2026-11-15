local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace('markdo.inline_progress')
local states = {}

local function clear(buf)
  if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
    api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end
end
local function draw(buf, parents)
  clear(buf)
  for _, parent in ipairs(parents or {}) do
    api.nvim_buf_set_extmark(buf, namespace, parent.row, 0, {
      virt_text = { { ('  %d/%d · %d%%'):format(parent.completed, parent.total, parent.percent), 'Comment' } },
      virt_text_pos = 'eol', hl_mode = 'combine',
    })
  end
end
local function queue(buf, state)
  if not state.enabled or state.pending then return end
  state.pending = true
  vim.schedule(function()
    state.pending = false
    if states[buf] ~= state or not state.enabled or not api.nvim_buf_is_loaded(buf) then return end
    if vim.bo[buf].filetype ~= 'markdown' then state.enabled = false; clear(buf); return end
    -- Parser errors hide annotations and retry on the next edit, without spam.
    draw(buf, require('markdo.progress').parents(buf))
  end)
end

api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout', 'FileType' }, {
  group = api.nvim_create_augroup('MarkDoInlineProgress', { clear = true }),
  callback = function(ev)
    if ev.event == 'FileType' and vim.bo[ev.buf].filetype == 'markdown' then return end
    local state = states[ev.buf]
    if state then state.enabled = false; clear(ev.buf) end
    if ev.event ~= 'FileType' then states[ev.buf] = nil end
  end,
})

function M.toggle(buf)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  local state = states[buf]
  if state and state.enabled then
    state.enabled = false
    clear(buf)
    return false
  end
  local parents, err = require('markdo.progress').parents(buf)
  if not parents then return nil, err end
  if not state then
    state = { enabled = false }
    states[buf] = state
    -- Attach once per buffer. API edits, insert-mode edits, undo and redo all
    -- queue a refresh; the scheduled callback runs outside on_lines textlock.
    local attached = api.nvim_buf_attach(buf, false, {
      on_lines = function() queue(buf, state) end,
      on_reload = function() queue(buf, state) end,
      on_detach = function() if states[buf] == state then states[buf] = nil end end,
    })
    if not attached then states[buf] = nil; return nil, 'Could not watch buffer' end
  end
  state.enabled = true
  draw(buf, parents)
  return true
end
return M
