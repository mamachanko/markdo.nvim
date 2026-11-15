-- Discover the health module through the real command, outside Markdown.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.g.loaded_clipboard_provider = 1 -- A deterministic missing optional provider.
vim.cmd('checkhealth markdo')
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(text:find('Mark Do: Neovim', 1, true), text)
assert(text:find('recognizes tasks and fenced blocks', 1, true), text)
assert(text:find('No clipboard provider', 1, true), text)
assert(text:find('Named fence shells on PATH:', 1, true), text)
assert(not text:find('ERROR', 1, true), text)
assert(vim.bo.filetype == 'checkhealth', vim.bo.filetype)
print('Real :checkhealth markdo discovery and rendering passed')
vim.cmd.qa({ bang = true })
