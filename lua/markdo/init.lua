local M = {}
local parse = require('markdo.parse')
function M.setup(opts) require('markdo.config').setup(opts) end
local function message(text) vim.notify('Mark Do: ' .. text, vim.log.levels.INFO) end
local function copy_body(body)
  if vim.fn.has('clipboard') ~= 1 then message('No clipboard provider; configure g:clipboard or install a clipboard tool'); return end
  local ok, result = pcall(vim.fn.setreg, '+', body, 'v')
  if not ok or result ~= 0 then message('Clipboard failed: ' .. tostring(result)) end
end
local function read()
  local data, err = parse.read(vim.api.nvim_get_current_buf())
  if not data then message(err) end
  return data
end
local function apply_changes(buf, changes)
  local cursor = vim.api.nvim_win_get_cursor(0)
  -- Start a fresh undo block even for consecutive API calls; join only our edits.
  vim.cmd('let &undolevels = &undolevels')
  for i, t in ipairs(changes) do
    if i > 1 then vim.cmd.undojoin() end
    vim.api.nvim_buf_set_text(buf, t.row, t.col + 1, t.row, t.col + 2, { t.checked and 'x' or ' ' })
  end
  vim.api.nvim_win_set_cursor(0, cursor)
end
local function change(toggle)
  local data = read(); if not data then return end
  local task = data:task_at(vim.api.nvim_win_get_cursor(0)[1] - 1)
  if not task then message('No task at cursor'); return end
  if not toggle and task.checked then return true end
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
  apply_changes(data.buf, changes)
  return true
end
function M.done() change(false) end
function M.toggle() change(true) end
function M.reset(scope)
  local data = read(); if not data then return end
  local changes, err = require('markdo.reset').prepare(data, vim.api.nvim_win_get_cursor(0)[1] - 1, scope)
  if not changes then message(err); return end
  if #changes == 0 then message('Tasks already open'); return end
  apply_changes(data.buf, changes)
end
local function navigate(direction, legacy)
  local data = read(); if not data then return end
  local options = require('markdo.config').navigation()
  local parents = {}
  if not legacy and options.leaf_only then
    for _, task in ipairs(data.tasks) do if task.parent then parents[task.parent] = true end end
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local tick = vim.api.nvim_buf_get_changedtick(data.buf)
  local first, last = 1, #data.tasks
  if direction < 0 then first, last = last, first end
  for i = first, last, direction do
    local task = data.tasks[i]
    if not task.checked and not parents[task] and (task.row - row) * direction > 0 then
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { task.row + 1, task.col })
      vim.cmd('normal! zv')
      if not legacy and options.copy_on_jump and vim.api.nvim_get_current_buf() == data.buf
        and vim.api.nvim_buf_get_changedtick(data.buf) == tick then
        -- Only one fence directly owned by the destination task is unambiguous.
        -- Never open a picker or borrow another task's fence during a motion.
        local chosen
        for _, fence in ipairs(data.fences) do
          if fence.owner == task then
            if chosen then return end
            chosen = fence
          end
        end
        if chosen then
          local body = parse.body(data, chosen)
          if body then copy_body(body) end
        end
      end
      return
    end
  end
  message(direction > 0 and 'No next unfinished task' or 'No previous unfinished task')
end
function M.done_next()
  -- Retain the original combined action for existing configurations. New
  -- navigation preferences and clipboard side effects apply only to Next/Prev.
  if change(false) then navigate(1, true) end
end
function M.next() navigate(1) end
function M.prev() navigate(-1) end
function M.progress(buf) return require('markdo.progress').get(buf) end
function M.show_progress()
  local progress, err = M.progress()
  if not progress then message(err); return end
  if progress.total == 0 then message('No tasks'); return end
  message(('%d/%d tasks complete (%d%%)'):format(progress.completed, progress.total, progress.percent))
end
function M.toggle_inline_progress()
  local enabled, err = require('markdo.inline').toggle()
  if enabled == nil then message(err); return end
  message('Inline progress ' .. (enabled and 'enabled' or 'disabled'))
end
function M.toggle_focus()
  local enabled, err = require('markdo.focus').toggle()
  if enabled == nil then message(err); return end
  message('Focus ' .. (enabled and 'enabled' or 'disabled'))
end
local function fence_action(action)
  local data = read(); if not data then return end
  local win = vim.api.nvim_get_current_win()
  local cwd = vim.fn.getcwd(0)
  parse.select(data, vim.api.nvim_win_get_cursor(win)[1] - 1, function(fence, err)
    if not fence then message(err); return end
    local body, why = parse.body(data, fence)
    if not body then message(why); return end
    action(body, fence.lang, cwd, { data = data, fence = fence })
  end)
end
function M.copy()
  fence_action(copy_body)
end
function M.run()
  local runner = require('markdo.runner')
  if runner.focus() then return end
  fence_action(function(body, lang, cwd, source) runner.run(body, lang, cwd, source) end)
end
function M.capture()
  local ok, err = require('markdo.capture').insert(vim.api.nvim_get_current_buf())
  message(ok and 'Output captured' or err)
end
function M.attach(buf)
  if vim.bo[buf].filetype ~= 'markdown' then return end
  for suffix, action in pairs({
    Done = 'done', DoneNext = 'done_next', Toggle = 'toggle', Copy = 'copy', Run = 'run', Capture = 'capture',
    Next = 'next', Prev = 'prev', Progress = 'show_progress',
    ProgressToggle = 'toggle_inline_progress', Reset = 'reset', FocusToggle = 'toggle_focus',
  }) do
    local callback = M[action]
    local options = { desc = 'Mark Do: ' .. action, force = true }
    if action == 'reset' then
      callback = function(opts) M.reset(opts.args) end
      options.nargs = '?'
      options.complete = function(lead)
        return vim.tbl_filter(function(scope) return vim.startswith(scope, lead) end, { 'task', 'section', 'buffer' })
      end
    end
    vim.api.nvim_buf_create_user_command(buf, 'MarkDo' .. suffix, callback, options)
    vim.keymap.set('n', '<Plug>(MarkDo' .. suffix .. ')', M[action], { buffer = buf, silent = true, desc = 'Mark Do: ' .. action })
  end
end
return M
