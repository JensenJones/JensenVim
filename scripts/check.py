#!/usr/bin/env python3
"""Validate source syntax and run isolated tests without Git or downloads.

Exit codes: 0 passed (with explicit skips), 1 tests failed, 2 prerequisites,
syntax, or test selection failed. Optional integration tests use local caches.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tokenize
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', '.worktrees', '.venv', 'venv', '__pycache__', 'node_modules', 'dist', 'build'}


def source_files():
    python, lua = [], []
    for directory, folders, names in os.walk(ROOT):
        folders[:] = sorted(name for name in folders if name not in EXCLUDED)
        for name in sorted(names):
            path = Path(directory)/name
            if path.suffix == '.py':
                python.append(path)
            elif path.suffix == '.lua':
                lua.append(path)
            elif path.parent == ROOT/'bin':
                with path.open('rb') as source:
                    if b'python' in source.readline():
                        python.append(path)
    return python, lua


def syntax_checks():
    python, lua = source_files()
    valid = True
    for path in python:
        try:
            with tokenize.open(path) as source:
                compile(source.read(), str(path), 'exec')
        except (SyntaxError, UnicodeError, OSError) as error:
            print(f'Python syntax error: {path}: {error}', file=sys.stderr)
            valid = False
    if not valid:
        return False
    nvim = shutil.which('nvim')
    if not nvim:
        print('Neovim 0.12+ is required for Lua syntax checks; install nvim on PATH.', file=sys.stderr)
        return False
    with tempfile.TemporaryDirectory(prefix='jvim-syntax-') as directory:
        manifest = Path(directory)/'files.json'
        manifest.write_text(json.dumps([str(path) for path in lua]))
        script = Path(directory)/'syntax.lua'
        script.write_text('''
if vim.fn.has('nvim-0.12') ~= 1 then
  io.stderr:write('Neovim 0.12+ is required for validation\\n')
  os.exit(1)
end
local files = vim.json.decode(table.concat(vim.fn.readfile(vim.env.JVIM_CHECK_MANIFEST), '\\n'))
local failed = false
for _, path in ipairs(files) do
  local chunk, problem = loadfile(path)
  if not chunk then io.stderr:write(tostring(problem) .. '\\n'); failed = true end
end
if failed then os.exit(1) end
vim.cmd('qa!')
''')
        env = dict(os.environ, JVIM_CHECK_MANIFEST=str(manifest))
        try:
            result = subprocess.run([nvim, '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f'Neovim syntax validation could not run: {error}', file=sys.stderr)
            return False
        if result.returncode:
            print(result.stderr or result.stdout or 'Neovim syntax validation failed', file=sys.stderr)
            return False
    print(f'Syntax passed: {len(python)} Python and {len(lua)} Lua files.', flush=True)
    return True


def main():
    if os.name == 'nt' and not sys.flags.utf8_mode:
        # Tests read and write UTF-8 sources; match the macOS/Linux default instead of the ANSI code page.
        return subprocess.call([sys.executable, '-X', 'utf8', *sys.argv])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pattern', default='test_*.py', help='unittest discovery pattern')
    parser.add_argument('--syntax-only', action='store_true', help='check syntax without running tests')
    args = parser.parse_args()
    if not syntax_checks():
        return 2
    if args.syntax_only:
        return 0
    sys.path.insert(0, str(ROOT))
    suite = unittest.defaultTestLoader.discover(str(ROOT/'tests'), pattern=args.pattern)
    if suite.countTestCases() == 0:
        print(f'No tests match {args.pattern!r}.', file=sys.stderr)
        return 2
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    passed = result.testsRun - sum(len(items) for items in (
        result.failures, result.errors, result.skipped, result.expectedFailures, result.unexpectedSuccesses))
    print(f'Validation: {passed} passed, {len(result.skipped)} skipped, '
          f'{len(result.failures)} failed, {len(result.errors)} errors.', flush=True)
    if result.expectedFailures or result.unexpectedSuccesses:
        print(f'Expected failures: {len(result.expectedFailures)}; unexpected successes: {len(result.unexpectedSuccesses)}.')
    for test, reason in result.skipped:
        print(f'SKIP {test.id()}: {reason}')
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
