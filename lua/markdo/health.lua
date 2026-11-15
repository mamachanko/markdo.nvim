local M = {}

function M.check()
  local health = vim.health
  health.start('Mark Do: Neovim')
  local version = vim.version()
  local label = ('Neovim %d.%d.%d'):format(version.major, version.minor, version.patch)
  if vim.fn.has('nvim-0.11') == 1 then
    health.ok(label .. ' (requires 0.11+)')
  else
    health.error(label .. ' is too old', { 'Upgrade to Neovim 0.11 or newer.' })
  end

  health.start('Mark Do: Markdown parser')
  local ok, err = pcall(function()
    -- Parse a string rather than the health window or any user buffer. Check
    -- the block node types Mark Do uses, not just the presence of a library.
    local parser = vim.treesitter.get_string_parser('- [ ] task\n\n```sh\nprintf ok\n```\n', 'markdown')
    local trees = parser:parse()
    local found = {}
    local function visit(node)
      found[node:type()] = true
      for child in node:iter_children() do visit(child) end
    end
    visit(assert(trees[1], 'no Markdown syntax tree'):root())
    assert(found.task_list_marker_unchecked and found.fenced_code_block,
      'parser lacks expected Markdown block nodes')
  end)
  if ok then
    health.ok('Markdown block parser loads and recognizes tasks and fenced blocks')
  else
    health.error('Markdown block parser unavailable or incompatible: ' .. tostring(err), {
      'Install or update it with :TSInstall markdown using nvim-treesitter.',
      'Alternatively, add a compatible parser/markdown.so to runtimepath; official Neovim releases include it.',
    })
  end

  health.start('Mark Do: Copy (optional)')
  local provider_ok, available = pcall(vim.fn.has, 'clipboard')
  if provider_ok and available == 1 then
    health.ok('Clipboard provider available for Copy')
  else
    local reason = provider_ok and 'No clipboard provider; Copy is unavailable'
      or ('Clipboard provider could not initialize: ' .. tostring(available))
    health.warn(reason, {
      'Install a platform clipboard tool or configure g:clipboard; see :help clipboard.',
      'Run :checkhealth vim.provider for clipboard-provider details.',
    })
  end

  health.start('Mark Do: Run (optional)')
  local platform = vim.uv.os_uname().sysname
  if platform == 'Linux' or platform == 'Darwin' then
    health.ok('Floating terminal runs supported on ' .. platform)
  else
    health.warn('Run is supported on Linux and macOS; detected ' .. platform, {
      'Use Linux or macOS for shell execution. Other Mark Do actions can still be used.',
    })
  end
  local shell, flag = vim.o.shell, vim.o.shellcmdflag
  health.info(('Configured shell=%q; shellcmdflag=%q'):format(shell, flag))
  -- Match the runner's argv construction; never invoke a shell to probe it.
  local args = vim.fn.split(shell)
  if args[1] and vim.fn.executable(args[1]) == 1 then
    health.ok('Configured shell executable available: ' .. args[1])
  else
    health.warn('Configured shell executable missing; shell-labelled fences are unavailable', {
      "Set 'shell' to an installed executable, for example :set shell=/bin/sh.",
      'Named sh/bash/zsh/fish fences use their own executables and may still work.',
    })
  end
  local command_flag_in_shell = false
  for i = 2, #args do
    if args[i]:match('^%-[a-zA-Z]*c[a-zA-Z]*$') then command_flag_in_shell = true end
  end
  if flag:match('^%s*$') and not command_flag_in_shell then
    health.warn('shellcmdflag is empty; verify how the configured shell accepts a script argument', {
      'For sh, bash, zsh or fish, use :set shellcmdflag=-c; otherwise see :help shellcmdflag.',
    })
  end
  local available_shells = {}
  for _, name in ipairs({ 'sh', 'bash', 'zsh', 'fish' }) do
    if vim.fn.executable(name) == 1 then available_shells[#available_shells + 1] = name end
  end
  health.info('Named fence shells on PATH: ' .. (#available_shells > 0 and table.concat(available_shells, ', ') or 'none'))
  health.info('Only the interpreter named by a fence is required; you do not need every supported shell.')
end
return M
