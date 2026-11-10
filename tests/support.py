"""Shared helpers for tests that run Neovim in an isolated home directory."""
import os
from pathlib import Path

XDG_NAMES = ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME')


def isolated_env(home, unset=(), **overrides):
    """Return an environment whose Neovim config, data, state and cache live under ``home``.

    On macOS and Linux, Neovim derives those directories from HOME, so this is
    ``dict(os.environ, HOME=home)``. Windows Neovim uses LOCALAPPDATA instead, so
    there the XDG variables (honoured on every platform) are pointed into ``home``;
    otherwise tests would read and write the real jvim installation.
    """
    env = dict(os.environ, HOME=str(home))
    for name in unset:
        env.pop(name, None)
    if os.name == 'nt':
        home = Path(home)
        env.update(XDG_CONFIG_HOME=str(home/'.config'), XDG_DATA_HOME=str(home/'.local/share'),
                   XDG_STATE_HOME=str(home/'.local/state'), XDG_CACHE_HOME=str(home/'.cache'))
    env.update(overrides)
    return env


def state_dir(home, app='nvim'):
    """Neovim's stdpath('state') for ``app`` inside an ``isolated_env`` home."""
    return Path(home)/'.local/state'/(app + '-data' if os.name == 'nt' else app)


def _local_appdata():
    return Path(os.environ.get('LOCALAPPDATA') or Path.home()/'AppData/Local')


def jvim_data():
    """Where an installed jvim keeps plugins (lazy/), parsers (site/) and Mason tools."""
    return _local_appdata()/'jvim-data' if os.name == 'nt' else Path.home()/'.local/share/jvim'


def nvim_plugins():
    """A lazy.nvim plugin directory for integration tests (the developer's nvim on macOS/Linux, jvim's on Windows)."""
    return jvim_data()/'lazy' if os.name == 'nt' else Path.home()/'.local/share/nvim/lazy'
