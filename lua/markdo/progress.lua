local M = {}
local cache = {}
local api = vim.api

api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
  group = api.nvim_create_augroup('MarkDoProgress', { clear = true }),
  callback = function(ev) cache[ev.buf] = nil end,
})

local function copy(count)
  return { total = count.total, completed = count.completed, percent = count.percent }
end
local function percent(count)
  return count.total > 0 and math.floor(count.completed * 100 / count.total + 0.5) or nil
end
local function read_entry(buf)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  if type(buf) ~= 'number' or not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then
    return nil, 'Buffer is not loaded'
  end
  if vim.bo[buf].filetype ~= 'markdown' then return nil, 'Not a Markdown buffer' end
  local tick = api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then return cache[buf] end
  local data, err = require('markdo.parse').read(buf)
  if not data then return nil, err end
  local has_children, counts = {}, {}
  for _, task in ipairs(data.tasks) do
    counts[task] = { total = 0, completed = 0 }
    if task.parent then has_children[task.parent] = true end
  end
  local entry = { tick = tick, total = 0, completed = 0, parents = {} }
  -- Parser traversal puts children after parents; accumulate each subtree once.
  for i = #data.tasks, 1, -1 do
    local task = data.tasks[i]
    local count = counts[task]
    if not has_children[task] then count.total = 1; count.completed = task.checked and 1 or 0 end
    local parent = task.parent and counts[task.parent] or entry
    parent.total = parent.total + count.total
    parent.completed = parent.completed + count.completed
  end
  entry.percent = percent(entry)
  for _, task in ipairs(data.tasks) do
    if has_children[task] then
      local count = counts[task]
      count.percent = percent(count)
      local summary = copy(count)
      summary.row = task.row
      entry.parents[#entry.parents + 1] = summary
    end
  end
  cache[buf] = entry
  return entry
end

-- Quiet and cached for statusline callers. Return copies so callers cannot
-- change cached results. A zero-task buffer has no meaningful percentage.
function M.get(buf)
  local entry, err = read_entry(buf)
  if not entry then return nil, err end
  return copy(entry)
end

-- Shared subtree counts for inline annotations; rows are zero-based.
function M.parents(buf)
  local entry, err = read_entry(buf)
  if not entry then return nil, err end
  local parents = {}
  for _, summary in ipairs(entry.parents) do
    local result = copy(summary)
    result.row = summary.row
    parents[#parents + 1] = result
  end
  return parents
end
return M
