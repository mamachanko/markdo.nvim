-- Isolate the provider cache from the main suite's fake clipboard.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.g.loaded_clipboard_provider = 1
local notice
vim.notify = function(s) notice = s end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '```', 'copy me', '```' })
vim.fn.setreg('a', 'keep-a')
vim.fn.setreg('"', 'keep-unnamed')
require('markdo').copy()
assert(notice and notice:find('No clipboard provider'), notice)
assert(vim.fn.getreg('a') == 'keep-a')
assert(vim.fn.getreg('"') == 'keep-unnamed')
vim.cmd.qa({ bang = true })
