"""Accept real completion items and fill their arguments through terminal keys."""
from pathlib import Path
import shutil
import unittest

from tests.support import jvim_data
from tests import test_terminal_startup as terminal

ROOT = Path(__file__).resolve().parents[1]
BLINK = jvim_data()/'lazy/blink.cmp'
LUASNIP = BLINK.parent/'LuaSnip'


class CompletionTests(unittest.TestCase):
    @unittest.skipUnless(terminal.pty is not None and shutil.which('nvim') and BLINK.is_dir() and LUASNIP.is_dir()
                         and all((terminal.PLUGINS/name).is_dir() for name in terminal.DEPENDENCIES),
                         'A POSIX pty, Neovim, Blink, LuaSnip and tree dependencies required')
    def test_completion_arguments_are_selected_and_sessions_end_cleanly(self):
        terminal.TerminalStartupTests().check_startup(True, 'completion_placeholders')
