local M = {}
local function children(node, fn)
  for child in node:iter_children() do fn(child); children(child, fn) end
end
local function contains(node, row)
  local sr, _, er, ec = node:range()
  return row >= sr and (row < er or (row == er and ec > 0))
end
function M.read(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok then
    return nil, 'Markdown Tree-sitter parser required; install it with :TSInstall markdown (nvim-treesitter) or add parser/markdown to runtimepath'
  end
  local success, trees = pcall(parser.parse, parser)
  if not success or not trees[1] then return nil, 'Could not parse Markdown' end
  local data = { buf = buf, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), tasks = {}, fences = {}, headings = {}, item_tails = {} }
  local function visit(node, owner)
    local kind = node:type()
    if kind == 'list_item' then
      local sr, _, er, ec = node:range()
      local last = ec == 0 and er - 1 or er
      local trimmed = last
      while trimmed > sr and data.lines[trimmed + 1]:match('^%s*$') do trimmed = trimmed - 1 end
      if trimmed < last then data.item_tails[#data.item_tails + 1] = { trimmed + 1, last } end
      for c in node:iter_children() do
        if c:type():match('^task_list_marker_') then
          local row, col = c:range()
          local task = { node = node, row = row, col = col, checked = c:type() == 'task_list_marker_checked', parent = owner }
          data.tasks[#data.tasks + 1] = task
          owner = task
          break
        end
      end
    elseif kind == 'fenced_code_block' then
      local fence = { node = node, owner = owner, delimiters = {}, prefixes = {} }
      children(node, function(c)
        local t = c:type()
        if t == 'fenced_code_block_delimiter' then fence.delimiters[#fence.delimiters + 1] = c
        elseif t == 'info_string' then fence.lang = vim.treesitter.get_node_text(c, buf):match('^%s*(%S+)')
        elseif t == 'block_continuation' then
          local r, _, _, col = c:range(); fence.prefixes[r] = col
        end
      end)
      fence.row = node:range()
      data.fences[#data.fences + 1] = fence
      return
    elseif kind == 'atx_heading' or kind == 'setext_heading' then
      data.headings[#data.headings + 1] = node:range()
    end
    for c in node:iter_children() do visit(c, owner) end
  end
  visit(trees[1]:root())
  function data:task_at(row)
    if not self.lines[row + 1] then return nil end
    for _, tail in ipairs(self.item_tails) do if row >= tail[1] and row <= tail[2] then return nil end end
    local chosen
    for _, task in ipairs(self.tasks) do if contains(task.node, row) then chosen = task end end
    return chosen
  end
  return data
end
function M.select(data, row, callback)
  for _, fence in ipairs(data.fences) do
    local last = fence.delimiters[2]
    local endrow = last and last:range()
    if contains(fence.node, row) and (not endrow or row <= endrow) then callback(fence); return end
  end
  local task = data:task_at(row)
  local candidates = {}
  if task then
    for _, f in ipairs(data.fences) do if f.owner == task then candidates[#candidates + 1] = f end end
  else
    local boundary = #data.lines
    for _, r in ipairs(data.headings) do if r > row then boundary = r; break end end
    for _, f in ipairs(data.fences) do
      if not f.owner and f.row > row and f.row < boundary then candidates = { f }; break end
    end
  end
  if #candidates == 0 then callback(nil, 'No fence in this scope'); return end
  if #candidates == 1 then callback(candidates[1]); return end
  local tick = vim.api.nvim_buf_get_changedtick(data.buf)
  vim.ui.select(candidates, {
    prompt = 'Mark Do fence:',
    format_item = function(f)
      local body = M.body(data, f)
      return ('%s · line %d · %s'):format(f.lang or 'unlabelled', f.row + 1, body and body:match('[^\n]*%S[^\n]*') or '(empty/incomplete)')
    end,
  }, function(choice)
    if not choice then return end
    if not vim.api.nvim_buf_is_valid(data.buf) or not vim.api.nvim_buf_is_loaded(data.buf)
      or vim.api.nvim_buf_get_changedtick(data.buf) ~= tick then
      callback(nil, 'Source changed; retry the command'); return
    end
    callback(choice)
  end)
end
function M.body(data, fence)
  if #fence.delimiters < 2 then return nil, 'Incomplete fence' end
  local opening = fence.delimiters[1]
  local first = opening:range()
  local last = fence.delimiters[2]:range()
  local indent = #(vim.treesitter.get_node_text(opening, data.buf):match('^ *') or '')
  local lines = {}
  for row = first + 1, last - 1 do
    local line = data.lines[row + 1]:sub((fence.prefixes[row] or 0) + 1)
    local removed = 0
    while removed < indent and line:match('^[ \t]') do
      local width = line:sub(1, 1) == '\t' and (4 - removed % 4) or 1
      line = line:sub(2)
      if removed + width > indent then line = string.rep(' ', removed + width - indent) .. line end
      removed = removed + width
    end
    lines[#lines + 1] = line
  end
  local body = table.concat(lines, '\n')
  if not body:find('%S') then return nil, 'Empty fence' end
  return body
end
return M
