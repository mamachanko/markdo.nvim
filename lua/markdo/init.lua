local M = {}
local parse = require('markdo.parse')
local function message(text) vim.notify('Mark Do: ' .. text, vim.log.levels.INFO) end
local function read()
  local data, err = parse.read(vim.api.nvim_get_current_buf())
  if not data then message(err) end
  return data
end
local function change(toggle)
  local data = read(); if not data then return end
  local task = data:task_at(vim.api.nvim_win_get_cursor(0)[1] - 1)
  if not task then message('No task at cursor'); return end
  if not toggle and task.checked then return end
  task.checked = not task.checked
  local changes = { task }
  local parent = task.parent
  while parent do
    local all = true
    for _, descendant in ipairs(data.tasks) do
      local ancestor = descendant.parent
      while ancestor do
        if ancestor == parent and not descendant.checked then all = false end
        ancestor = ancestor.parent
      end
    end
    if parent.checked ~= all then parent.checked = all; changes[#changes + 1] = parent end
    parent = parent.parent
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  -- Start a fresh undo block even for consecutive API calls; join only our edits.
  vim.cmd('let &undolevels = &undolevels')
  for i, t in ipairs(changes) do
    if i > 1 then vim.cmd.undojoin() end
    vim.api.nvim_buf_set_text(data.buf, t.row, t.col + 1, t.row, t.col + 2, { t.checked and 'x' or ' ' })
  end
  vim.api.nvim_win_set_cursor(0, cursor)
end
function M.done() change(false) end
function M.toggle() change(true) end
local function navigate(direction)
  local data = read(); if not data then return end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local first, last = 1, #data.tasks
  if direction < 0 then first, last = last, first end
  for i = first, last, direction do
    local task = data.tasks[i]
    if not task.checked and (task.row - row) * direction > 0 then
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { task.row + 1, task.col })
      vim.cmd('normal! zv')
      return
    end
  end
  message(direction > 0 and 'No next unfinished task' or 'No previous unfinished task')
end
function M.next() navigate(1) end
function M.prev() navigate(-1) end
local function fence_action(action)
  local data = read(); if not data then return end
  local win = vim.api.nvim_get_current_win()
  local cwd = vim.fn.getcwd(0)
  parse.select(data, vim.api.nvim_win_get_cursor(win)[1] - 1, function(fence, err)
    if not fence then message(err); return end
    local body, why = parse.body(data, fence)
    if not body then message(why); return end
    action(body, fence.lang, cwd)
  end)
end
function M.copy()
  fence_action(function(body)
    if vim.fn.has('clipboard') ~= 1 then message('No clipboard provider; configure g:clipboard or install a clipboard tool'); return end
    local ok, err = pcall(vim.fn.setreg, '+', body, 'v')
    if not ok then message('Clipboard failed: ' .. tostring(err)) end
  end)
end
function M.run()
  local runner = require('markdo.runner')
  if runner.focus() then return end
  fence_action(function(body, lang, cwd) runner.run(body, lang, cwd) end)
end
function M.attach(buf)
  if vim.bo[buf].filetype ~= 'markdown' then return end
  for suffix, action in pairs({ Done = 'done', Toggle = 'toggle', Copy = 'copy', Run = 'run', Next = 'next', Prev = 'prev' }) do
    vim.api.nvim_buf_create_user_command(buf, 'MarkDo' .. suffix, M[action], { desc = 'Mark Do: ' .. action, force = true })
    vim.keymap.set('n', '<Plug>(MarkDo' .. suffix .. ')', M[action], { buffer = buf, silent = true, desc = 'Mark Do: ' .. action })
  end
end
return M
