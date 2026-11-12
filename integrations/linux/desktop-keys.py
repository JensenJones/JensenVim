#!/usr/bin/env python3
"""List GNOME desktop shortcuts that take keys jvim uses in WezTerm; --apply hands those keys to jvim.

Only the clashing accelerator is removed from each setting, so other bindings for the same
action (for example Super+Page Up for switching workspaces) keep working. Undo one with
`gsettings reset <schema> <key>`.
"""
import ast
from pathlib import Path
import re
import shutil
import subprocess
import sys

KEY_TABLE = Path(__file__).resolve().parents[1]/'wezterm/jvim.lua'
KEY_NAMES = {'leftarrow': 'left', 'rightarrow': 'right', 'uparrow': 'up', 'downarrow': 'down', 'enter': 'return',
             'backspace': 'backspace', '-': 'minus', '=': 'equal', ';': 'semicolon', '\\\\': 'backslash', '\\': 'backslash',
             '/': 'slash', '[': 'bracketleft', ']': 'bracketright', ',': 'comma', '.': 'period', "'": 'apostrophe', '|': 'bar'}
MODIFIERS = {'cmd': 'control', 'ctrl': 'control', 'control': 'control', 'primary': 'control', 'alt': 'alt',
             'shift': 'shift', 'super': 'super'}


def jvim_keys():
    keys = set()
    for key, mods in re.findall(r"^\s*\{ '((?:[^'\\]|\\.)+)', '([A-Z|]+)'", KEY_TABLE.read_text(), re.M):
        if mods != 'NONE':
            keys.add((frozenset(MODIFIERS[mod.lower()] for mod in mods.split('|')), KEY_NAMES.get(key.lower(), key.lower())))
    return keys


def parse_accelerator(text):
    mods = frozenset(MODIFIERS.get(mod.lower(), mod.lower()) for mod in re.findall(r'<([^>]+)>', text))
    key = re.sub(r'<[^>]+>', '', text).lower()
    return mods, key


def label(mods, key):
    names = [name for name in ('control', 'alt', 'shift', 'super') if name in mods]
    return '+'.join([name.capitalize() if name != 'control' else 'Ctrl' for name in names] + [key.capitalize()])


def clashes():
    taken = jvim_keys()
    schemas = subprocess.run(['gsettings', 'list-schemas'], capture_output=True, text=True, check=True).stdout.split()
    found = []
    for schema in sorted(s for s in schemas if s.endswith('keybindings') or s.endswith('media-keys')):
        listing = subprocess.run(['gsettings', 'list-recursively', schema], capture_output=True, text=True, check=True).stdout
        for line in listing.splitlines():
            parts = line.split(' ', 2)
            if len(parts) < 3:
                continue
            value = re.sub(r'^@as ', '', parts[2].strip())
            try:
                parsed = ast.literal_eval(value)
            except (ValueError, SyntaxError):
                continue
            accelerators = parsed if isinstance(parsed, list) else [parsed] if isinstance(parsed, str) else []
            hits = [a for a in accelerators if a and parse_accelerator(a) in taken]
            if hits:
                kept = [a for a in accelerators if a not in hits]
                new = repr(kept) if isinstance(parsed, list) else "''"
                found.append((schema, parts[1], hits, new))
    return found


def main():
    if not shutil.which('gsettings'):
        return 0
    found = clashes()
    if not found:
        print('No desktop shortcuts clash with jvim.')
        return 0
    apply = '--apply' in sys.argv[1:]
    print('These desktop shortcuts ' + ('were handed to jvim:' if apply else 'take keys jvim uses in WezTerm:'))
    for schema, key, hits, new in found:
        print(f"  {', '.join(label(*parse_accelerator(a)) for a in hits)}: {schema} {key}")
        if apply:
            subprocess.run(['gsettings', 'set', schema, key, new], check=True)
    if not apply:
        print(f'To give them to jvim (undo with gsettings reset <schema> <key>), run: {Path(__file__).resolve()} --apply')
    return 0


if __name__ == '__main__':
    sys.exit(main())
