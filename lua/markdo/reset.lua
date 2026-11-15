local M = {}
function M.prepare(data, row, scope)
  if type(scope) == 'string' then scope = vim.trim(scope) end
  if scope == nil or scope == '' then scope = 'task' end
  if scope ~= 'task' and scope ~= 'section' and scope ~= 'buffer' then
    return nil, 'Unknown reset scope; use task, section, or buffer'
  end
  local task, section
  if scope == 'task' then
    task = data:task_at(row)
    if not task then return nil, 'No task at cursor' end
  elseif scope == 'section' then
    section = data:section_at(row)
  end
  local selected = {}
  for _, candidate in ipairs(data.tasks) do
    local include = scope == 'buffer'
    if task then
      local ancestor = candidate
      while ancestor do
        if ancestor == task then include = true; break end
        ancestor = ancestor.parent
      end
    elseif section then
      local first, last, col = section.first, section.last, section.last_col
      include = candidate.row >= first and (candidate.row < last or candidate.row == last and col > 0)
    end
    if include then selected[#selected + 1] = candidate end
  end
  if #selected == 0 then return nil, 'No tasks in this ' .. scope end
  local changes, seen = {}, {}
  -- Reset only reopens tasks. Every ancestor of a changed task necessarily
  -- has an open descendant afterwards, so it must reopen too.
  local function reopen(candidate)
    if candidate.checked and not seen[candidate] then
      candidate.checked = false
      seen[candidate] = true
      changes[#changes + 1] = candidate
    end
  end
  for _, candidate in ipairs(selected) do
    if candidate.checked then
      reopen(candidate)
      local parent = candidate.parent
      while parent do reopen(parent); parent = parent.parent end
    end
  end
  return changes
end
return M
