#!/usr/bin/env python3
"""Install the Mac integration. Preview by default; --apply changes files."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid
import venv

SOURCE = Path(__file__).resolve().parents[1]
XDG_PATHS = ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME')


def check_environment():
    overrides = [name for name in XDG_PATHS if os.environ.get(name)]
    if overrides:
        raise RuntimeError('Custom XDG paths are not supported by the jvim installer: '
                           + ', '.join(overrides) + '. Unset them before installing and launching jvim.')


def publish(replacements, home, backup, stage, registration_app=None):
    """Replace only owned paths and restore them if publishing fails."""
    changed = []
    try:
        for target, prepared in replacements:
            saved = backup/target.relative_to(home)
            target.parent.mkdir(parents=True, exist_ok=True)
            existed = target.exists() or target.is_symlink()
            if existed:
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(saved))
            changed.append((target, saved, existed))
            if prepared is not None:
                shutil.move(str(prepared), str(target))
        if registration_app:
            subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                            '-f', str(registration_app)], check=True)
    except BaseException as failure:
        # Move replacements aside rather than deleting anything during recovery.
        recovery_errors = []
        for target, saved, existed in reversed(changed):
            try:
                if target.exists() or target.is_symlink():
                    displaced = stage/'rollback'/target.relative_to(home)
                    displaced.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(target), str(displaced))
                if existed:
                    shutil.move(str(saved), str(target))
            except OSError as error:
                recovery_errors.append(f'{target}: {error}')
        if recovery_errors:
            raise RuntimeError(f'Installation failed ({failure}); recovery incomplete. '
                               f'Restore previous files from {backup}: '+ '; '.join(recovery_errors)) from failure
        print('Installation failed; previous managed files restored.')
        raise


def install(home, *, apply=False, runtime=True, registration=True):
    check_environment()
    home = Path(home).expanduser().resolve()
    config = home/'.config/jvim'
    share = home/'.local/share/jvim'
    bindir = home/'.local/bin'
    profile = home/'Library/Application Support/iTerm2/DynamicProfiles/jvim.json'
    shared_names = ['host-profile.applescript', 'open-location.applescript', 'requirements.txt', 'runtime.json']
    if runtime:
        shared_names.append('runtime')
    if registration:
        shared_names.append('JvimLinks.app')
    targets = [config, *(share/name for name in shared_names), profile,
               *(bindir/name for name in ('jvim', 'jvim-host-profile', 'jvim-open-location'))]
    legacy = profile.with_name('neovim-clion.json')
    legacy_remaining = None
    if legacy.exists():
        try:
            legacy_data = json.loads(legacy.read_text())
            if any(p.get('Name') == 'jvim' for p in legacy_data.get('Profiles', [])):
                targets.append(legacy)
                legacy_remaining = dict(legacy_data, Profiles=[p for p in legacy_data['Profiles'] if p.get('Name') != 'jvim'])
        except (ValueError, OSError, TypeError, AttributeError):
            raise RuntimeError(f'Cannot inspect existing legacy profile: {legacy}; resolve it before installing.')
    print('Managed destinations (plugin, parser and Mason caches are preserved):')
    for target in targets:
        print(' ', target)
    if not apply:
        print('Preview only. Run ./install-macos.sh --apply to install.')
        return
    nvim = shutil.which('nvim')
    if not nvim:
        raise RuntimeError('Install Neovim first (for example: brew install neovim ripgrep).')
    if registration:
        for tool in ('osacompile', 'codesign'):
            if not shutil.which(tool):
                raise RuntimeError(f'Missing required Mac utility: {tool}')
    prefs_path = home/'Library/Preferences/com.googlecode.iterm2.plist'
    try:
        prefs = plistlib.loads(prefs_path.read_bytes()) if prefs_path.exists() else {}
        parent = next((p for p in prefs.get('New Bookmarks', []) if p.get('Guid') == prefs.get('Default Bookmark Guid')), {})
        keys = dict(parent.get('Keyboard Map', {}))
        keys.update(json.loads((SOURCE/'integrations/macos/keyboard.json').read_text()))
    except (ValueError, OSError, TypeError, AttributeError, plistlib.InvalidFileException) as error:
        raise RuntimeError(f'Cannot read iTerm preferences; existing installation unchanged: {prefs_path}: {error}') from error
    preset = {'Name': 'jvim', 'Guid': '6FC6F216-7CB9-4E4F-A44B-E20639FF49B8', 'Keyboard Map': keys}
    if parent.get('Guid'):
        preset['Dynamic Profile Parent GUID'] = parent['Guid']
    install_id = datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
    backup = home/'.local/state/jvim/backups'/install_id
    # All copied files and Mac app preparation finish before replacing active files.
    with tempfile.TemporaryDirectory(prefix='jvim-install-') as temporary:
        stage = Path(temporary)
        replacements = []
        def prepared(target):
            path = stage/'prepared'/target.relative_to(home)
            path.parent.mkdir(parents=True, exist_ok=True)
            replacements.append((target, path))
            return path
        shutil.copytree(SOURCE/'config', prepared(config), ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.DS_Store'))
        for name in ('host-profile.applescript', 'open-location.applescript', 'requirements.txt'):
            shutil.copy2(SOURCE/'integrations/macos'/name, prepared(share/name))
        for name in ('jvim', 'jvim-host-profile', 'jvim-open-location'):
            content = (SOURCE/'bin'/name).read_text()
            path = prepared(bindir/name)
            # A shell/Python polyglot keeps the exact interpreter even when its
            # path contains spaces; kernels cannot quote a shebang interpreter.
            trampoline = "#!/bin/sh\n'''exec' "+shlex.quote(sys.executable)+" \"$0\" \"$@\"\n' '''\n"
            path.write_text(trampoline+content.split('\n', 1)[1])
            path.chmod(0o755)
        prepared(share/'runtime.json').write_text(json.dumps({'nvim': nvim, 'parent_profile': parent.get('Name')})+'\n')
        prepared(profile).write_text(json.dumps({'Profiles': [preset]}, indent=2)+'\n')
        if legacy_remaining is not None:
            if legacy_remaining['Profiles']:
                prepared(legacy).write_text(json.dumps(legacy_remaining, indent=2)+'\n')
            else:
                replacements.append((legacy, None))
        app = None
        if registration:
            app = prepared(share/'JvimLinks.app')
            subprocess.run(['osacompile', '-o', str(app), str(SOURCE/'integrations/macos/open-location.applescript')], check=True)
            info_path = app/'Contents/Info.plist'
            info = plistlib.loads(info_path.read_bytes())
            info.update(LSUIElement=True, CFBundleIdentifier='local.jensen.jvim.links', CFBundleURLTypes=[{'CFBundleURLName':'JensenVim definitions', 'CFBundleURLSchemes':['jvim-definition']}])
            info_path.write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
        if runtime:
            # Venv scripts contain absolute paths: build at their permanent location,
            # then publish a symlink. Older runtimes remain available for rollback.
            versioned_runtime = share/'runtimes'/install_id
            versioned_runtime.parent.mkdir(parents=True, exist_ok=True)
            print('Preparing Python runtime:', versioned_runtime)
            try:
                venv.EnvBuilder(with_pip=True).create(versioned_runtime)
                subprocess.run([str(versioned_runtime/'bin/python3'), '-m', 'pip', 'install', '-r', str(SOURCE/'integrations/macos/requirements.txt')], check=True)
            except BaseException:
                print('Runtime preparation failed; active installation unchanged. Unused preparation:', versioned_runtime)
                raise
            prepared(share/'runtime').symlink_to(versioned_runtime, target_is_directory=True)
        publish(replacements, home, backup, stage, share/'JvimLinks.app' if app else None)
    print('Installed. Add ~/.local/bin to PATH, enable iTerm Settings > General > Magic > Python API, then run jvim .')
    print('First launch may download plugins/tools according to your jvim settings. This installer does not run Git or open terminal windows.')
    if backup.exists():
        print('Previous managed files saved to:', backup)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This installer requires macOS. See install-windows.ps1 for the Windows core.')
    try:
        install(Path.home(), apply=args.apply)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit('Installation stopped: '+str(error))
