if vim.g.loaded_markdo then return end
vim.g.loaded_markdo = true
if vim.fn.has('nvim-0.11') ~= 1 then
  vim.notify('Mark Do requires Neovim 0.11+', vim.log.levels.ERROR)
  return
end
local group = vim.api.nvim_create_augroup('MarkDo', { clear = true })
vim.api.nvim_create_autocmd('FileType', { group = group, pattern = 'markdown', callback = function(ev)
  require('markdo').attach(ev.buf)
end })
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then require('markdo').attach(buf) end
end
