-- Window fold snapshots. Use Neovim's view writer to capture manual fold
-- definitions and open/closed exceptions, but replay only whitelisted fold ops.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('markdo.focus_snapshot')
local option_names = { 'foldmethod', 'foldexpr', 'foldtext', 'foldenable', 'foldlevel',
  'foldminlines', 'foldnestmax', 'foldcolumn', 'foldmarker', 'foldignore' }
local function command(cmd, args, bang)
  api.nvim_cmd({ cmd = cmd, args = args or {}, bang = bang or false,
    mods = { silent = true, noautocmd = true, keepalt = true, keepjumps = true } }, {})
end
local function anchor(snapshot, first, last)
  local id = api.nvim_buf_set_extmark(snapshot.buf, ns, first - 1, 0, {
    end_row = last, end_col = 0, right_gravity = true, end_right_gravity = false,
    invalidate = true, undo_restore = true,
  })
  snapshot.ids[#snapshot.ids + 1] = id
  return id
end
local function range(snapshot, id)
  local value = api.nvim_buf_get_extmark_by_id(snapshot.buf, ns, id, { details = true })
  if #value == 0 or value[3].invalid then return end
  local last = value[3].end_row + (value[3].end_col > 0 and 1 or 0)
  last = math.min(last, api.nvim_buf_line_count(snapshot.buf))
  if value[1] < last then return value[1] + 1, last end
end
function M.discard(snapshot)
  if api.nvim_buf_is_valid(snapshot.buf) then
    for _, id in ipairs(snapshot.ids) do pcall(api.nvim_buf_del_extmark, snapshot.buf, ns, id) end
  end
end
function M.capture(win)
  local snapshot = { buf = api.nvim_win_get_buf(win), options = {}, ids = {}, operations = {} }
  local ok, err = pcall(api.nvim_win_call, win, function()
    for _, name in ipairs(option_names) do snapshot.options[name] = vim.wo[name] end
    snapshot.view = vim.fn.winsaveview()
    local path, viewoptions, buftype = vim.fn.tempname(), vim.o.viewoptions, vim.bo.buftype
    local unnamed = api.nvim_buf_get_name(snapshot.buf) == ''
    local saved, result = pcall(function()
      -- mkview omits folds for unnamed buffers. A temporary virtual name lets
      -- it serialize them; suppress filename hooks and preserve the alternate.
      if buftype ~= '' then command('setlocal', { 'buftype=' }) end
      if unnamed then command('file', { 'markdo-focus://snapshot/' .. win }) end
      command('set', { 'viewoptions=folds,cursor' })
      command('mkview', { path }, true)
      return vim.fn.readfile(path)
    end)
    if unnamed then vim.cmd("noautocmd keepalt lua vim.api.nvim_buf_set_name(0, '')") end
    if vim.bo.buftype ~= buftype then command('setlocal', { 'buftype=' .. buftype }) end
    command('set', { 'viewoptions=' .. viewoptions })
    vim.fn.delete(path)
    if not saved then error(result) end
    local address
    for _, line in ipairs(result) do
      -- 0.12 adds :sil! to fold definitions and state commands.
      line = line:gsub('^sil! ', ''):gsub('^silent! ', '')
      local first, last = line:match('^(%d+),(%d+)fold$')
      local op = line:match('^normal! (z[oOcC])$')
      if first then
        snapshot.operations[#snapshot.operations + 1] = { kind = 'fold', id = anchor(snapshot, tonumber(first), tonumber(last)) }
      elseif line == 'let &fdl = &fdl' then
        snapshot.operations[#snapshot.operations + 1] = { kind = 'level' }
      elseif line:match('^%d+$') then
        address = anchor(snapshot, tonumber(line), tonumber(line))
      elseif op and address then
        snapshot.operations[#snapshot.operations + 1] = { kind = op, id = address }
      end
    end
    snapshot.cursor = api.nvim_buf_set_extmark(snapshot.buf, ns, snapshot.view.lnum - 1, snapshot.view.col, {})
    snapshot.top = api.nvim_buf_set_extmark(snapshot.buf, ns, snapshot.view.topline - 1, 0, {})
    snapshot.ids[#snapshot.ids + 1] = snapshot.cursor
    snapshot.ids[#snapshot.ids + 1] = snapshot.top
  end)
  if not ok then M.discard(snapshot); return nil, 'Could not save folds: ' .. tostring(err) end
  return snapshot
end
local function saved_view(snapshot)
  local view = vim.deepcopy(snapshot.view)
  local cursor = api.nvim_buf_get_extmark_by_id(snapshot.buf, ns, snapshot.cursor, {})
  local top = api.nvim_buf_get_extmark_by_id(snapshot.buf, ns, snapshot.top, {})
  if #cursor > 0 then view.lnum, view.col = cursor[1] + 1, cursor[2] end
  if #top > 0 then view.topline = top[1] + 1 end
  return view
end
function M.restore(win, snapshot, view)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= snapshot.buf then return end
  api.nvim_win_call(win, function()
    vim.wo.foldmethod = 'manual'
    vim.cmd('silent! normal! zE')
    for _, name in ipairs(option_names) do
      if name ~= 'foldmethod' and name ~= 'foldenable' then vim.wo[name] = snapshot.options[name] end
    end
    vim.wo.foldmethod = snapshot.options.foldmethod
    vim.wo.foldenable = true
    if vim.wo.foldmethod ~= 'manual' then vim.cmd('silent! normal! zx') end
    for _, op in ipairs(snapshot.operations) do
      if op.kind == 'level' then
        vim.wo.foldlevel = snapshot.options.foldlevel
      else
        local first, last = range(snapshot, op.id)
        if first then
          if op.kind == 'fold' then
            if vim.wo.foldmethod == 'manual' then vim.cmd(('silent! keepjumps %d,%dfold'):format(first, last)) end
          else
            vim.cmd('silent! keepjumps ' .. first)
            vim.cmd('silent! normal! ' .. op.kind)
          end
        end
      end
    end
    vim.wo.foldenable = snapshot.options.foldenable
    vim.fn.winrestview(view or saved_view(snapshot))
  end)
end
return M
