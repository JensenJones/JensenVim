"""Trusted external settings and company overlays must preserve host tooling."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim required')
class ConfigTests(unittest.TestCase):
    def lua(self, body, personal=None, **environment):
        with tempfile.TemporaryDirectory(prefix='jvim-config-') as directory:
            home = Path(directory)
            if personal is not None:
                user = home/'.config/jvim-user/init.lua'
                user.parent.mkdir(parents=True)
                user.write_text(personal)
            script = home/'check.lua'
            script.write_text("vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)\n" + body + "\nvim.cmd('qa!')\n")
            env = dict(os.environ, HOME=directory, NVIM_APPNAME='jvim', JVIM_TEST_CONFIG=str(ROOT/'config'))
            for name in ('JVIM_CONFIG', 'JVIM_PROFILE', 'JVIM_OFFLINE', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME'):
                env.pop(name, None)
            env.update(environment)
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_external_profile_and_explicit_overrides_replace_arrays(self):
        self.lua("""
local config=require 'jvim.config'
local opts=config.setup {lsp={servers={clangd={cmd={'final-clangd'}}}}}
assert(opts.tools.mason==false)
assert(opts.formatting.on_save==false)
assert(vim.deep_equal(opts.lsp.servers.clangd.cmd,{'final-clangd'}))
assert(opts.lsp.servers.lua_ls==false)
assert(config.source():find('jvim%-user/init.lua$'))
assert(config.profile()=='work')
""", personal="return {lsp={servers={clangd={cmd={'personal-clangd','--flag'}}}},profiles={work={tools={mason=false},formatting={on_save=false},lsp={servers={lua_ls=false}}}}}", JVIM_PROFILE='work')

    def test_offline_policy_disables_every_download_path(self):
        self.lua("""
local opts=require('jvim.config').setup {offline=true,plugins={install=true},tools={install=true},treesitter={auto_install=true}}
assert(not opts.plugins.install and not opts.tools.install and not opts.treesitter.auto_install)
assert(opts.completion.fuzzy=='lua')
""")

    def test_environment_offline_is_a_final_override(self):
        self.lua("assert(require('jvim.config').setup({offline=false}).offline)", JVIM_OFFLINE='1')

    def test_invalid_personal_config_fails_closed(self):
        self.lua("""
local config=require 'jvim.config'
local opts=config.setup {}
assert(opts.offline and not opts.plugins.install and not opts.tools.install)
assert(#config.errors()>0)
""", personal="error('broken company settings')")

    def test_invalid_explicit_options_fail_before_side_effects(self):
        self.lua("""
local config=require 'jvim.config'
assert(not pcall(config.setup,{tools={mason='yes'}}))
assert(not pcall(config.setup,{unexpected=true}))
assert(not pcall(config.setup,{lsp={servers={clangd={cmd={'clangd',false}}}}}))
""")

    def test_overlay_defaults_preserve_company_management(self):
        self.lua("""
local opts=require('jvim.config').setup {mode='overlay'}
assert(not opts.plugins.enabled and not opts.tools.mason and not opts.tools.install)
assert(not opts.lsp.default_servers and not opts.treesitter.auto_install)
assert(not opts.formatting.on_save and not opts.features.autosave)
assert(not opts.ui.theme and not opts.ui.statusline and not opts.ui.tabline)
""")

    def test_overlay_startup_is_idempotent_and_does_not_start_tooling(self):
        self.lua("""
vim.fn.system=function() error('overlay executed external bootstrap') end
vim.system=function() error('overlay started a process') end
package.preload.lazy=function() error('overlay replaced the plugin manager') end
local jvim=require 'jvim'
jvim.setup {mode='overlay'}
local before=#vim.api.nvim_get_autocmds({})
local paste=vim.paste
jvim.setup {mode='overlay'}
assert(#vim.api.nvim_get_autocmds({})==before,'repeated setup duplicated autocmds')
assert(vim.paste==paste,'repeated setup wrapped paste twice')
assert(#vim.lsp.get_clients()==0)
assert(vim.fn.maparg('<F4>','i')~='','editing bindings were not installed')
""")

    def test_standard_plugin_entry_preserves_host_namespace_and_explorer(self):
        self.lua("""
vim.opt.rtp:remove(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:prepend(vim.fs.dirname(vim.env.JVIM_TEST_CONFIG))
package.preload['custom.keymaps']=function() error('company namespace was replaced') end
vim.g.loaded_netrwPlugin=0
local before,after=0,0
require('jvim').setup {before_setup=function() before=before+1 end,after_setup=function() after=after+1 end}
assert(before==1 and after==1)
assert(package.loaded['custom.keymaps']==nil)
assert(vim.g.loaded_netrwPlugin==0,'overlay replaced host explorer')
assert(require('jvim').get_config().mode=='overlay')
""")

    def test_server_overrides_disable_defaults_without_enabling_a_formatter_as_lsp(self):
        self.lua("""
local config=require 'jvim.config'
config.setup {lsp={servers={clangd={cmd={'company-clangd'}},lua_ls=false}}}
local servers=require('jvim.lsp').servers()
assert(vim.deep_equal(servers.clangd.cmd,{'company-clangd'}))
assert(servers.lua_ls==false and servers.stylua==nil)
""")

    def test_offline_fresh_start_uses_core_without_network(self):
        self.lua("""
vim.fn.system=function() error('offline bootstrap executed Git') end
vim.system=function() error('offline startup executed a process') end
require('jvim').setup {mode='standalone',offline=true}
assert(not vim.g.jvim_plugins_ready)
assert(vim.fn.maparg('<F4>','i')~='','core editor did not remain usable')
""")

    def test_offline_cached_manager_never_repins_or_installs_missing_plugins(self):
        self.lua("""
local config=require 'jvim.config'
local opts=config.setup {offline=true,tools={mason=false}}
local path=vim.fn.stdpath('data')..'/lazy/lazy.nvim'
vim.fn.mkdir(path,'p')
local observed
package.preload.lazy=function() return {setup=function(specs,options) observed=options;assert(#specs>0) end} end
vim.fn.system=function() error('offline cache pin invoked Git') end
vim.system=function() error('offline cache started a process') end
assert(require('jvim.bootstrap').setup(opts))
assert(observed.install.missing==false and observed.checker.enabled==false)
""")

    def test_unsupported_neovim_fails_before_loading_personal_code(self):
        self.lua("""
local has=vim.fn.has
vim.fn.has=function(feature) return feature=='nvim-0.12' and 0 or has(feature) end
local ok,err=pcall(require('jvim').setup,{})
assert(not ok and tostring(err):find('Neovim 0.12'),tostring(err))
assert(not vim.g.personal_loaded)
""", personal="vim.g.personal_loaded=true; return {}")

    def test_disabled_tabline_does_not_initialise_mini_tabline(self):
        self.lua("""
require('jvim.config').setup {ui={tabline=false,statusline=false}}
for _,name in ipairs({'mini.ai','mini.surround'}) do package.preload[name]=function() return {setup=function() end} end end
package.preload['mini.tabline']=function() error('disabled tabline was loaded') end
package.preload['mini.statusline']=function() error('disabled statusline was loaded') end
for _,spec in ipairs(require('jvim.plugins')) do
  if spec[1]=='nvim-mini/mini.nvim' then spec.config() end
end
""")

    def test_native_server_setup_survives_without_optional_plugins(self):
        self.lua("""
local enabled={}
vim.lsp.config=function() end
vim.lsp.enable=function(name) enabled[name]=true end
require('jvim').setup {mode='standalone',plugins={enabled=false},lsp={servers={clangd={cmd={'company-clangd'}}}}}
assert(enabled.clangd,'explicit native server was not enabled')
""")

    def test_core_tree_and_format_actions_are_safe_without_plugins(self):
        self.lua("""
require('jvim').setup {mode='standalone',offline=true}
local notifications={}
vim.notify=function(message) notifications[#notifications+1]=message end
assert(pcall(require('jvim.files').focus_tree))
vim.api.nvim_buf_set_lines(0,0,-1,false,{'unchanged'})
local formatted=false
vim.lsp.buf.format=function() formatted=true end
vim.fn.maparg('<F24>','i',false,true).callback()
assert(vim.wait(500,function() return formatted end))
assert(#notifications>0,'missing tree did not report dependency')
""")

    def test_lsp_highlights_are_unique_and_cleared_after_last_client_detaches(self):
        self.lua("""
require('jvim.config').setup {tools={mason=false},lsp={default_servers=false}}
local client={id=2,supports_method=function() return true end,stop=function() end}
local attached=true
vim.lsp.get_client_by_id=function() return client end
vim.lsp.get_clients=function() return attached and {client} or {} end
require('jvim.lsp').setup()
local buf=vim.api.nvim_get_current_buf()
for id=1,2 do vim.api.nvim_exec_autocmds('LspAttach',{buffer=buf,data={client_id=id}}) end
local function count() return #vim.api.nvim_get_autocmds({group='jvim-lsp',event={'CursorHold','CursorHoldI'},buffer=buf}) end
assert(count()==2,'multiple servers duplicated highlight callbacks')
vim.api.nvim_exec_autocmds('LspDetach',{buffer=buf,data={client_id=1}})
vim.wait(20)
assert(count()==2,'remaining client lost highlighting')
attached=false
vim.api.nvim_exec_autocmds('LspDetach',{buffer=buf,data={client_id=2}})
assert(vim.wait(100,function() return count()==0 end),'detached buffer retained highlighting')
""")
