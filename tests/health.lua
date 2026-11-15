return function(eq)
  local health = require('markdo.health')
  local report = {}
  local saved = { health = vim.health, version = vim.version, has = vim.fn.has,
    executable = vim.fn.executable, uname = vim.uv.os_uname, parser = vim.treesitter.get_string_parser,
    shell = vim.o.shell, flag = vim.o.shellcmdflag, jobstart = vim.fn.jobstart,
    system = vim.fn.system, setreg = vim.fn.setreg, getreg = vim.fn.getreg }
  local platform, supported, clipboard = 'Linux', true, true
  local executables = { ['/bin/sh'] = true, sh = true, bash = true }
  vim.health = {}
  for _, severity in ipairs({ 'start', 'ok', 'info', 'warn', 'error' }) do
    vim.health[severity] = function(message, advice)
      report[#report + 1] = { severity = severity, message = message, advice = advice }
    end
  end
  vim.version = function() return { major = 0, minor = supported and 11 or 10, patch = 0 } end
  vim.fn.has = function(feature)
    if feature == 'nvim-0.11' then return supported and 1 or 0 end
    if feature == 'clipboard' then return clipboard and 1 or 0 end
    return saved.has(feature)
  end
  vim.fn.executable = function(name) return executables[name] and 1 or 0 end
  vim.uv.os_uname = function() return { sysname = platform } end
  vim.o.shell, vim.o.shellcmdflag = '/bin/sh', '-c'
  local function forbidden() error('health must not execute jobs or access clipboard contents') end
  vim.fn.jobstart, vim.fn.system, vim.fn.setreg, vim.fn.getreg = forbidden, forbidden, forbidden, forbidden
  local function find(severity, fragment)
    for _, entry in ipairs(report) do
      if entry.severity == severity and entry.message:find(fragment, 1, true) then return entry end
    end
  end
  local function count(severity)
    local n = 0
    for _, entry in ipairs(report) do if entry.severity == severity then n = n + 1 end end
    return n
  end
  local function run() report = {}; health.check() end
  run()
  eq(count('start'), 4); eq(count('error'), 0); eq(count('warn'), 0)
  eq(find('ok', '0.11.0') ~= nil, true)
  eq(find('ok', 'recognizes tasks and fenced blocks') ~= nil, true)
  eq(find('ok', 'Clipboard provider available') ~= nil, true)
  eq(find('info', 'Named fence shells on PATH: sh, bash') ~= nil, true)
  eq(find('info', 'shellcmdflag="-c"') ~= nil, true)
  -- Missing unselected interpreters never cause individual warnings.
  executables = { ['/bin/sh'] = true }
  run(); eq(count('warn'), 0); eq(find('info', 'PATH: none') ~= nil, true)
  platform = 'Darwin'; run(); eq(find('ok', 'supported on Darwin') ~= nil, true)
  platform = 'Windows_NT'; run()
  eq(count('error'), 0); eq(find('warn', 'supported on Linux and macOS') ~= nil, true)
  platform = 'Linux'; supported = false; clipboard = false
  run()
  eq(find('error', '0.10.0 is too old').advice[1], 'Upgrade to Neovim 0.11 or newer.')
  eq(find('warn', 'No clipboard provider').advice[2]:find(':checkhealth vim.provider', 1, true) ~= nil, true)
  supported, clipboard = true, true
  -- Parser loading failures and incompatible grammars are core errors.
  vim.treesitter.get_string_parser = function() error('no markdown parser') end
  run()
  eq(find('error', 'parser unavailable or incompatible') ~= nil, true)
  eq(find('error', 'parser unavailable').advice[1]:find(':TSInstall markdown', 1, true) ~= nil, true)
  eq(find('ok', 'Configured shell executable available') ~= nil, true) -- Check continues.
  vim.treesitter.get_string_parser = function()
    return { parse = function() return { { root = function()
      return { type = function() return 'document' end, iter_children = function() return function() end end }
    end } } end }
  end
  run(); eq(find('error', 'expected Markdown block nodes') ~= nil, true)
  vim.treesitter.get_string_parser = saved.parser
  -- A broken provider is an optional warning, not an aborted health check.
  vim.fn.has = function(feature)
    if feature == 'clipboard' then error('invalid clipboard configuration') end
    return saved.has(feature)
  end
  run(); eq(find('warn', 'could not initialize') ~= nil, true)
  eq(count('error'), 0)
  vim.fn.has = function(feature) return feature == 'clipboard' and 1 or saved.has(feature) end
  vim.o.shell = '/missing-markdo-shell'
  run(); eq(find('warn', 'Configured shell executable missing') ~= nil, true)
  eq(count('error'), 0)
  vim.o.shell = ''
  run(); eq(find('warn', 'Configured shell executable missing') ~= nil, true)
  vim.o.shell, vim.o.shellcmdflag = '/bin/sh', ''
  run(); eq(find('warn', 'shellcmdflag is empty') ~= nil, true)
  vim.o.shell = '/bin/sh -e'
  run(); eq(find('warn', 'shellcmdflag is empty') ~= nil, true)
  vim.o.shell = '/bin/sh -c'
  run(); eq(find('warn', 'shellcmdflag is empty'), nil)
  eq(find('ok', 'Configured shell executable available: /bin/sh') ~= nil, true)
  -- Restore everything before the real runner and clipboard tests.
  vim.health, vim.version, vim.fn.has = saved.health, saved.version, saved.has
  vim.fn.executable, vim.uv.os_uname = saved.executable, saved.uname
  vim.treesitter.get_string_parser = saved.parser
  vim.o.shell, vim.o.shellcmdflag = saved.shell, saved.flag
  vim.fn.jobstart, vim.fn.system, vim.fn.setreg, vim.fn.getreg = saved.jobstart, saved.system, saved.setreg, saved.getreg
end
