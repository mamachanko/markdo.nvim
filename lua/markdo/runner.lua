local M = {}
local active
local function message(s) vim.notify('Mark Do: ' .. s, vim.log.levels.INFO) end
function M.focus()
  if not active then return false end
  if vim.api.nvim_win_is_valid(active.win) then
    vim.api.nvim_set_current_win(active.win); vim.cmd.startinsert()
  end
  return true
end
function M.run(body, lang, cwd)
  if M.focus() then return end
  local args
  if lang == 'shell' then
    args = vim.fn.split(vim.o.shell)
    vim.list_extend(args, vim.fn.split(vim.o.shellcmdflag))
  elseif vim.tbl_contains({ 'sh', 'bash', 'zsh', 'fish' }, lang or '') then args = { lang, '-c' }
  else message('Unsupported or unlabelled shell fence'); return end
  if not args[1] or vim.fn.executable(args[1]) ~= 1 then message('Shell executable missing: ' .. (args[1] or '')); return end
  args[#args + 1] = body
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local height = math.max(1, math.min(25, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height, row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)), title = ' Mark Do · running ', title_pos = 'center' })
  vim.bo[buf].bufhidden = 'hide'
  local state = { buf = buf, win = win }
  active = state
  local function stop() if state.job and not state.exited then vim.fn.jobstop(state.job) end end
  vim.keymap.set('n', 'x', stop, { buffer = buf, desc = 'Stop Mark Do job' })
  vim.keymap.set('n', 'q', function()
    if state.exited and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, desc = 'Close completed Mark Do run' })
  local group = vim.api.nvim_create_augroup('MarkDoRun' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', { group = group, pattern = tostring(win), callback = function()
    stop()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end)
  end })
  state.job = vim.fn.jobstart(args, { term = true, cwd = cwd, on_exit = function(_, code)
    state.exited = true
    if active == state then active = nil end
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, { title = (' Mark Do · exit %d '):format(code) })
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].markdo_exit_code = code
      end
    end)
  end })
  if state.job <= 0 then
    active = nil; state.exited = true; message('Could not start shell'); vim.api.nvim_win_close(win, true); return
  end
  vim.cmd.startinsert()
end
return M
