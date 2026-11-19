local M = {}
local function children(node, fn)
  for child in node:iter_children() do fn(child); children(child, fn) end
end
local function contains(node, row)
  local sr, _, er, ec = node:range()
  return row >= sr and (row < er or (row == er and ec > 0))
end
local function fence_ranges(root)
  local fences, code, markers, items = {}, {}, {}, {}
  local function visit(node)
    local kind = node:type()
    if kind:match('^task_list_marker_') then markers[#markers + 1] = { node:range() } end
    if kind == 'list_item' then
      for child in node:iter_children() do
        if child:type():match('^list_marker_') then
          local row, _, _, col = child:range()
          items[#items + 1] = { node = node, row = row, col = col }; break
        end
      end
    end
    if kind == 'fenced_code_block' or kind == 'indented_code_block' then
      local first, _, last, col = node:range()
      last = last - (col == 0 and 1 or 0)
      if kind == 'fenced_code_block' then
        local delimiters = {}
        children(node, function(child)
          if child:type() == 'fenced_code_block_delimiter' then delimiters[#delimiters + 1] = { child:range() } end
        end)
        fences[#fences + 1] = delimiters
        -- Container prefixes can extend the node into the following tag line.
        if delimiters[2] then last = delimiters[2][1] end
      end
      for row = first, last do code[row] = true end
      return
    end
    for child in node:iter_children() do visit(child) end
  end
  visit(root)
  return fences, code, markers, items
end
local function columns(prefix)
  local width = 0
  for char in prefix:gmatch('.') do width = width + (char == '\t' and 4 - width % 4 or 1) end
  return width
end
local function summary(tag)
  return (tag:match('^<summary>') or tag:match('^<summary%s')) and tag:match('</summary>%s*$')
end
local function recover_details(lines, tree)
  -- The bundled block grammar can put list markers inside ERROR nodes, or
  -- detach an entire child item, around HTML details/summary wrappers. Reparse
  -- a fixed-width view of standalone wrappers as ordinary continuation text.
  -- Keep code opaque and accept recovery only if it removes all parse errors
  -- without changing fence delimiters or losing existing checkbox markers.
  local root = tree:root()
  if not root:has_error() then return end
  local original_fences, code, original_markers, items = fence_ranges(root)
  local normalized, changed, wrappers = {}, false, {}
  local function blank(row, quotes)
    return not lines[row] or lines[row]:match('^[ \t]*$')
      or (quotes ~= '' and lines[row]:gsub('[ \t]', '') == quotes)
  end
  local function prelude(row, quotes)
    -- HTML blocks end at a blank line. Do not promote text that is still HTML
    -- into Markdown tasks/fences by removing its opening tags.
    if blank(row + 1, quotes) then return true end
    local next_tag = lines[row + 1]:match('^[ \t>]*(<.*)$')
    return next_tag and summary(next_tag:lower()) and blank(row + 2, quotes)
  end
  for i, line in ipairs(lines) do
    local prefix, tag = line:match('^([ \t>]*)(<.*)$')
    local wrapper = false
    if tag and not code[i - 1] then
      local lower = tag:lower()
      local width, quotes = columns(prefix), prefix:gsub('[ \t]', '')
      if lower:match('^<details>%s*$') or lower:match('^<details%s+[^<>]*>%s*$') then
        -- Only list-contained wrappers need this workaround. In particular,
        -- do not turn dedented HTML into lazy continuation of a previous task.
        if prelude(i, quotes) then
          for _, item in ipairs(items) do
            if contains(item.node, i - 1) and width >= columns(lines[item.row + 1]:sub(1, item.col)) then
              wrapper = true; break
            end
          end
          local parent = wrappers[#wrappers]
          wrapper = wrapper or (parent and quotes == parent.quotes and width >= parent.width)
        end
        if wrapper then wrappers[#wrappers + 1] = { width = width, quotes = quotes } end
      elseif lower:match('^</details>%s*$') then
        local parent = wrappers[#wrappers]
        if parent and quotes == parent.quotes and width == parent.width then
          wrapper = blank(i + 1, quotes); table.remove(wrappers)
        end
      elseif summary(lower) and blank(i + 1, quotes) then
        local parent = wrappers[#wrappers]
        wrapper = parent and quotes == parent.quotes and width >= parent.width
      end
    end
    normalized[i] = wrapper and (prefix .. string.rep('x', #line - #prefix)) or line
    changed = changed or wrapper
  end
  if not changed then return end
  local ok, parser, trees = pcall(function()
    local parser = vim.treesitter.get_string_parser(table.concat(normalized, '\n') .. '\n', 'markdown')
    return parser, parser:parse()
  end)
  if ok and trees and trees[1] and not trees[1]:root():has_error() then
    local fences, _, markers = fence_ranges(trees[1]:root())
    if not vim.deep_equal(original_fences, fences) then return end
    local found = {}
    for _, marker in ipairs(markers) do found[table.concat(marker, ':')] = true end
    for _, marker in ipairs(original_markers) do if not found[table.concat(marker, ':')] then return end end
    return parser, trees
  end
end
function M.read(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok then
    return nil, 'Markdown Tree-sitter parser required; install it with :TSInstall markdown (nvim-treesitter) or add parser/markdown to runtimepath'
  end
  local success, trees = pcall(parser.parse, parser)
  if not success or not trees[1] then return nil, 'Could not parse Markdown' end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local recovered_parser, recovered_trees = recover_details(lines, trees[1])
  if recovered_parser then parser, trees = recovered_parser, recovered_trees end
  local data = {
    buf = buf, lines = lines, _parser = parser,
    tasks = {}, fences = {}, headings = {}, heading_ranges = {}, sections = {}, item_tails = {},
  }
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
      local row = node:range()
      data.headings[#data.headings + 1] = row
      local heading_range = { first = row, last = row }
      data.heading_ranges[#data.heading_ranges + 1] = heading_range
      local level
      for child in node:iter_children() do
        if child:type():match('^setext_h[12]_underline$') then heading_range.last = child:range() end
        level = level or tonumber(child:type():match('^atx_h([1-6])_marker$')
          or child:type():match('^setext_h([12])_underline$'))
      end
      if level then
        local container = node:parent()
        while container:type() == 'section' do container = container:parent() end
        local _, _, last, col = container:range()
        data.sections[#data.sections + 1] = { first = row, last = last, last_col = col,
          level = level, container = container:id(), document = container:type() == 'document' }
      end
    end
    for c in node:iter_children() do visit(c, owner) end
  end
  visit(trees[1]:root())
  -- Setext headings are flat in the 0.11 parser's section nodes. Build the
  -- outline from parsed heading markers instead, bounded by their containers.
  local preamble = { first = 0, last = #data.lines, last_col = 0 }
  local stacks = {}
  for _, section in ipairs(data.sections) do
    if section.document then preamble.last = math.min(preamble.last, section.first) end
    local stack = stacks[section.container] or {}
    stacks[section.container] = stack
    while #stack > 0 and stack[#stack].level >= section.level do
      local previous = table.remove(stack)
      previous.last, previous.last_col = section.first, 0
    end
    stack[#stack + 1] = section
  end
  table.insert(data.sections, 1, preamble)
  function data:section_at(row)
    local chosen
    for _, section in ipairs(self.sections) do
      if row >= section.first and (row < section.last or row == section.last and section.last_col > 0) then
        chosen = section
      end
    end
    return chosen
  end
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
