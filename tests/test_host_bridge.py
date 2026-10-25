import asyncio
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class Properties:
    def set_key_mappings(self, keys):
        self.keys = keys


class Session:
    def __init__(self, ident):
        self.session_id = ident
        self.keys = {'baseline': 'original'}

    async def async_get_profile(self):
        return types.SimpleNamespace(key_mappings=self.keys)

    async def async_get_variable(self, name):
        return 'herdr'

    async def async_set_profile_properties(self, props):
        self.keys = props.keys

    async def async_set_variable(self, name, value):
        pass


class App:
    def __init__(self, sessions):
        self.sessions = sessions
        self.selected = None

    def get_session_by_id(self, ident):
        return next((s for s in self.sessions if s.session_id == ident), None)

    @property
    def terminal_windows(self):
        return [types.SimpleNamespace(tabs=[types.SimpleNamespace(sessions=self.sessions)])]

    @property
    def current_terminal_window(self):
        session = self.selected or (self.sessions[0] if self.sessions else None)
        return types.SimpleNamespace(current_tab=types.SimpleNamespace(current_session=session))

    async def async_refresh(self):
        pass


def load_bridge(fake):
    loader = importlib.machinery.SourceFileLoader('bridge_under_test', str(ROOT/'bin/jvim-host-profile'))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {'iterm2': fake}):
        loader.exec_module(module)
    return module


class BridgeTests(unittest.IsolatedAsyncioTestCase):
    async def test_missing_host_never_chooses_between_multiple_herdr_clients(self):
        bridge = load_bridge(types.ModuleType('iterm2'))
        with self.assertRaises(RuntimeError):
            await bridge.find_host(App([Session('one'), Session('two')]), 'gone', True)

    async def test_replacement_host_and_real_pane_focus_keep_shortcuts_scoped(self):
        fake = types.ModuleType('iterm2')
        old = Session('old')
        app = App([old])
        async def get_app(connection):
            return app
        class Profile:
            def __init__(self, name):
                self.name = name
            async def async_get_full_profile(self):
                return types.SimpleNamespace(key_mappings={'jvim': 'mapped'} if self.name == 'jvim' else {'baseline': 'original'})
        class PartialProfile:
            @staticmethod
            async def async_query(connection):
                return [Profile('jvim'), Profile('Default')]
        fake.async_get_app = get_app
        fake.PartialProfile = PartialProfile
        fake.LocalWriteOnlyProfile = Properties
        fake.rpc = types.SimpleNamespace(RPCException=type('FakeRPCError', (Exception,), {}))
        click_state = False
        async def get_preference(connection, key):
            return click_state
        async def set_preference(connection, key, value):
            nonlocal click_state
            click_state = value
        fake.PreferenceKey = types.SimpleNamespace(PASS_ON_CONTROL_CLICK='ctrlclick')
        fake.preferences = types.SimpleNamespace(async_get_preference=get_preference, async_set_preference=set_preference)
        bridge = load_bridge(fake)
        focused = True
        async def pane_focused(pane):
            return focused
        bridge.pane_focused = pane_focused
        async def eventually(predicate):
            for _ in range(50):
                if predicate():
                    return
                await asyncio.sleep(.05)
            self.fail('bridge did not reach expected state')
        with tempfile.TemporaryDirectory(prefix='jvim-bridge-') as tmp:
            home = Path(tmp)
            socket = str(home/'bridge.sock')
            env = {'HERDR_ENV': '1', 'HERDR_PANE_ID': 'test:pane'}
            argv = ['jvim-host-profile', '--serve', socket, 'old', 'Default', 'owner']
            with patch.dict(os.environ, env), patch.object(sys, 'argv', argv), patch.object(bridge.Path, 'home', return_value=home), contextlib.redirect_stdout(io.StringIO()):
                task = asyncio.create_task(bridge.main(None))
                try:
                    await eventually(lambda: old.keys == {'jvim': 'mapped'} and Path(socket).exists())
                    reader, writer = await asyncio.open_unix_connection(socket)
                    # A spurious FocusLost must not release keys while the pane
                    # remains focused in Herdr.
                    writer.write(b'blur\n')
                    await writer.drain()
                    self.assertEqual(await reader.readline(), b'OK\n')
                    self.assertEqual(old.keys, {'jvim': 'mapped'})
                    self.assertTrue(click_state)
                    app.selected = Session('another terminal window')
                    await eventually(lambda: old.keys == {'baseline': 'original'})
                    self.assertFalse(click_state)
                    app.selected = None
                    await eventually(lambda: old.keys == {'jvim': 'mapped'})
                    replacement = Session('replacement')
                    app.sessions = [replacement]
                    await eventually(lambda: replacement.keys == {'jvim': 'mapped'})
                    focused = False
                    await eventually(lambda: replacement.keys == {'baseline': 'original'})
                    self.assertFalse(click_state)
                    writer.write(b'stop\n')
                    await writer.drain()
                    self.assertEqual(await reader.readline(), b'OK\n')
                    writer.close()
                    await writer.wait_closed()
                    await asyncio.wait_for(task, 2)
                finally:
                    if not task.done():
                        task.cancel()
                        with contextlib.suppress(asyncio.CancelledError):
                            await task
