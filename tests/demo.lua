vim.opt.rtp:prepend(vim.fn.getcwd())
local demo = dofile('scripts/demo.lua')
vim.o.columns, vim.o.lines = demo.width, demo.height
demo.setup({ fixture_clipboard = true })
for _, step in ipairs(demo.steps) do
  demo.prepare(step.id)
  demo.press(step)
  demo.check(step.id)
  if step.id == 'health' then demo.health_details() end
end
demo.verify()
demo.finish()
assert(vim.fn.getreg('+') == 'previous test clipboard')
print('Complete demo passed through real keymaps, ending with Run and Capture')
vim.cmd.qa({ bang = true })
