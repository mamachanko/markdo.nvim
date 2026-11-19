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
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Heading', '- [ ] task', '  ```sh', '  echo hi', '  ```' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
require('markdo').setup({ navigation = { copy_on_jump = true } })
require('markdo').next()
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
assert(notice and notice:find('No clipboard provider'), notice)
assert(vim.fn.getreg('a') == 'keep-a')
assert(vim.fn.getreg('"') == 'keep-unnamed')
vim.cmd.qa({ bang = true })
