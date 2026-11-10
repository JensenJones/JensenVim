"""Health reports effective policy and dependencies without starting processes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tests.support import isolated_env

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim required')
class HealthTests(unittest.TestCase):
    def lua(self, body, personal=None):
        with tempfile.TemporaryDirectory(prefix='jvim-health-') as directory:
            home = Path(directory)
            if personal is not None:
                user = home/'.config/jvim-user/init.lua'
                user.parent.mkdir(parents=True)
                user.write_text(personal)
            script = home/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local reports = {}
for _, level in ipairs {'start', 'ok', 'info', 'warn', 'error'} do
  vim.health[level] = function(message) reports[#reports+1] = {level, tostring(message)} end
end
local function contains(level, needle)
  for _, report in ipairs(reports) do
    if report[1] == level and report[2]:find(needle, 1, true) then return true end
  end
  return false
end
local function require_report(level, needle)
  assert(contains(level, needle), level .. ': ' .. needle .. ' absent: ' .. vim.inspect(reports))
end
local function prohibit_processes()
  local function forbidden() error('health started an external process') end
  vim.system, vim.fn.system, vim.fn.systemlist, vim.fn.jobstart, vim.fn.termopen = forbidden, forbidden, forbidden, forbidden, forbidden
  package.preload.lazy = forbidden
  package.preload.mason = forbidden
end
''' + body + "\nvim.cmd('qa!')\n")
            env = isolated_env(directory, unset=('JVIM_CONFIG', 'JVIM_PROFILE', 'JVIM_OFFLINE', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME'),
                               NVIM_APPNAME='jvim', JVIM_TEST_CONFIG=str(ROOT/'config'))
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_offline_policy_and_missing_cache_are_reported_without_bootstrap(self):
        self.lua('''
require('jvim.config').setup {offline=true,tools={mason=false}}
prohibit_processes()
require('jvim.health').check()
require_report('info', 'Offline: enabled')
require_report('info', 'Mason: disabled')
require_report('info', 'Tool installation: disabled')
require_report('info', 'Parser installation: disabled')
require_report('warn', 'Lazy cache missing')
''')

    def test_company_profile_and_resolved_server_override_are_reported(self):
        self.lua('''
require('jvim.config').setup {profile='company'}
local exepath = vim.fn.exepath
vim.fn.exepath = function(command)
  if command == 'company-clangd' then return '/company tools/bin/clangd' end
  return exepath(command)
end
prohibit_processes()
require('jvim.health').check()
require_report('info', 'Profile: company')
require_report('info', 'jvim-user/init.lua')
require_report('ok', 'LSP clangd: /company tools/bin/clangd')
assert(not contains('warn', 'LSP lua_ls:') and not contains('ok', 'LSP lua_ls:'))
''', personal="return {tools={mason=false},lsp={default_servers=false,servers={clangd={cmd={'company-clangd','--company'}},lua_ls=false}},profiles={company={}}}")

    def test_personal_configuration_errors_are_reported_with_source(self):
        self.lua('''
require('jvim.config').setup {}
prohibit_processes()
require('jvim.health').check()
require_report('error', 'broken company settings')
require_report('info', 'jvim-user/init.lua')
require_report('info', 'Offline: enabled')
''', personal="error('broken company settings')")

    def test_neovim_minimum_and_optional_dependency_failures_are_actionable(self):
        # PDF support defaults off on Windows (image.nvim is unsupported there), so enable it explicitly.
        self.lua('''
require('jvim.config').setup { features = { pdf = true } }
local has = vim.fn.has
vim.fn.has = function(feature) if feature == 'nvim-0.12' then return 0 end return has(feature) end
vim.fn.exepath = function() return '' end
prohibit_processes()
require('jvim.health').check()
require_report('error', 'Neovim 0.12')
require_report('warn', 'Project search: rg missing')
require_report('warn', 'Python 3')
require_report('warn', 'PDF metadata: pdfinfo missing')
require_report('warn', 'PDF rendering: pdftoppm missing')
require_report('warn', 'ImageMagick')
''')

    def test_disabled_integrations_and_existing_lazy_cache_are_reported(self):
        self.lua('''
require('jvim.config').setup {mode='overlay',features={pdf=false}}
vim.fn.mkdir(vim.fn.stdpath('data') .. '/lazy/lazy.nvim/lua/lazy', 'p')
vim.fn.writefile({'return {}'},vim.fn.stdpath('data') .. '/lazy/lazy.nvim/lua/lazy/init.lua')
prohibit_processes()
require('jvim.health').check()
require_report('info', 'Mode: overlay')
require_report('ok', 'Lazy cache:')
require_report('info', 'PDF support: disabled')
require_report('info', 'Platform integration:')
assert(not contains('warn', 'PDF metadata:'))
''')
