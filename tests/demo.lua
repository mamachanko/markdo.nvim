vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 40, 18
local demo = dofile('scripts/demo.lua')
demo.setup({ fixture_clipboard = true })
for _, step in ipairs(demo.steps) do
  demo.prepare(step.id)
  vim.cmd(step.command)
  demo.check(step.id)
  if step.id == 'health' then demo.health_details() end
end
demo.send_input()
demo.check_running_output()
demo.check_exit()
demo.close_terminal()
demo.check_closed()
demo.finish()
assert(vim.fn.getreg('+') == 'previous test clipboard')
print('Complete demo scenario passed, with execution last')
vim.cmd.qa({ bang = true })
