local M = {}
local defaults = { leaf_only = true, copy_on_jump = false }
local navigation = vim.deepcopy(defaults)

function M.setup(opts)
  if opts == nil then opts = {} end
  if type(opts) ~= 'table' then error('markdo.setup: expected a table', 2) end
  for key in pairs(opts) do
    if key ~= 'navigation' then error('markdo.setup: unknown option ' .. tostring(key), 2) end
  end
  local supplied = opts.navigation
  if supplied ~= nil and type(supplied) ~= 'table' then error('markdo.setup: navigation must be a table', 2) end
  local next_navigation = vim.deepcopy(defaults)
  for key, value in pairs(supplied or {}) do
    if defaults[key] == nil then error('markdo.setup: unknown navigation option ' .. tostring(key), 2) end
    if type(value) ~= 'boolean' then error('markdo.setup: navigation.' .. key .. ' must be a boolean', 2) end
    next_navigation[key] = value
  end
  navigation = next_navigation
end

function M.navigation() return navigation end
return M
