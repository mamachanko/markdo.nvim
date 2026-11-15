local M = {}
local cache = {}
local api = vim.api

api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
  group = api.nvim_create_augroup('MarkDoProgress', { clear = true }),
  callback = function(ev) cache[ev.buf] = nil end,
})

-- Quiet and cached for statusline callers. Return a copy so callers cannot
-- change the cached result. A zero-task buffer has no meaningful percentage.
function M.get(buf)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  if type(buf) ~= 'number' or not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then
    return nil, 'Buffer is not loaded'
  end
  if vim.bo[buf].filetype ~= 'markdown' then return nil, 'Not a Markdown buffer' end
  local tick = api.nvim_buf_get_changedtick(buf)
  local entry = cache[buf]
  if not entry or entry.tick ~= tick then
    local data, err = require('markdo.parse').read(buf)
    if not data then return nil, err end
    local parents = {}
    for _, task in ipairs(data.tasks) do if task.parent then parents[task.parent] = true end end
    local completed, total = 0, 0
    for _, task in ipairs(data.tasks) do
      if not parents[task] then
        total = total + 1
        if task.checked then completed = completed + 1 end
      end
    end
    entry = { tick = tick, total = total, completed = completed,
      percent = total > 0 and math.floor(completed * 100 / total + 0.5) or nil }
    cache[buf] = entry
  end
  return { total = entry.total, completed = entry.completed, percent = entry.percent }
end
return M
