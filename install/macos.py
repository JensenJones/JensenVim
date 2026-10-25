#!/usr/bin/env python3
"""Install the Mac integration. Preview by default; --apply changes files."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import uuid
import venv

SOURCE = Path(__file__).resolve().parents[1]


def install(home, *, apply=False, runtime=True, registration=True):
    home = Path(home).expanduser().resolve()
    config = home/'.config/jvim'
    share = home/'.local/share/jvim'
    bindir = home/'.local/bin'
    profile = home/'Library/Application Support/iTerm2/DynamicProfiles/jvim.json'
    targets = [config, share, profile, *(bindir/name for name in ('jvim', 'jvim-host-profile', 'jvim-open-location'))]
    legacy = profile.with_name('neovim-clion.json')
    legacy_remaining = None
    if legacy.exists():
        try:
            legacy_data = json.loads(legacy.read_text())
            if any(p.get('Name') == 'jvim' for p in legacy_data.get('Profiles', [])):
                targets.append(legacy)
                legacy_remaining = dict(legacy_data, Profiles=[p for p in legacy_data['Profiles'] if p.get('Name') != 'jvim'])
        except (ValueError, OSError):
            raise RuntimeError(f'Cannot inspect existing legacy profile: {legacy}; resolve it before installing.')
    print('Managed destinations:')
    for target in targets:
        print(' ', target)
    if not apply:
        print('Preview only. Run ./install-macos.sh --apply to install.')
        return
    nvim = shutil.which('nvim')
    if not nvim:
        raise RuntimeError('Install Neovim first (for example: brew install neovim ripgrep).')
    if registration:
        for tool in ('osacompile', 'codesign', 'defaults'):
            if not shutil.which(tool):
                raise RuntimeError(f'Missing required Mac utility: {tool}')
    # The installer does not read or modify the existing ~/.config/nvim setup.
    backup = home/'.local/state/jvim/backups'/(datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])
    for target in targets:
        if target.exists() or target.is_symlink():
            dest = backup/target.relative_to(home)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), str(dest))
    if legacy_remaining and legacy_remaining['Profiles']:
        legacy.write_text(json.dumps(legacy_remaining, indent=2)+'\n')
    config.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE/'config', config)
    share.mkdir(parents=True, exist_ok=True)
    bindir.mkdir(parents=True, exist_ok=True)
    for name in ('host-profile.applescript', 'open-location.applescript', 'requirements.txt'):
        shutil.copy2(SOURCE/'integrations/macos'/name, share/name)
    for name in ('jvim', 'jvim-host-profile', 'jvim-open-location'):
        content = (SOURCE/'bin'/name).read_text()
        # LaunchServices has a minimal PATH; bind the interpreter on this machine.
        content = '#!'+sys.executable+'\n'+content.split('\n', 1)[1]
        (bindir/name).write_text(content)
        (bindir/name).chmod(0o755)
    prefs_path = home/'Library/Preferences/com.googlecode.iterm2.plist'
    prefs = plistlib.loads(prefs_path.read_bytes()) if prefs_path.exists() else {}
    parent = next((p for p in prefs.get('New Bookmarks', []) if p.get('Guid') == prefs.get('Default Bookmark Guid')), {})
    (share/'runtime.json').write_text(json.dumps({'nvim': nvim, 'parent_profile': parent.get('Name')})+'\n')
    keys = dict(parent.get('Keyboard Map', {}))
    keys.update(json.loads((SOURCE/'integrations/macos/keyboard.json').read_text()))
    preset = {'Name': 'jvim', 'Guid': '6FC6F216-7CB9-4E4F-A44B-E20639FF49B8', 'Keyboard Map': keys}
    if parent.get('Guid'):
        preset['Dynamic Profile Parent GUID'] = parent['Guid']
    profile.parent.mkdir(parents=True, exist_ok=True)
    profile.write_text(json.dumps({'Profiles': [preset]}, indent=2)+'\n')
    if runtime:
        venv.EnvBuilder(with_pip=True).create(share/'runtime')
        subprocess.run([str(share/'runtime/bin/python3'), '-m', 'pip', 'install', '-r', str(share/'requirements.txt')], check=True)
    if registration:
        app = share/'JvimLinks.app'
        subprocess.run(['osacompile', '-o', str(app), str(share/'open-location.applescript')], check=True)
        info_path = app/'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info.update(LSUIElement=True, CFBundleIdentifier='local.jensen.jvim.links', CFBundleURLTypes=[{'CFBundleURLName':'JensenVim definitions', 'CFBundleURLSchemes':['jvim-definition']}])
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', str(app)], check=True)
        subprocess.run(['defaults', 'write', 'com.googlecode.iterm2', 'UnderlineHyperlinks', '-bool', 'false'], check=True)
    print('Installed. Add ~/.local/bin to PATH, enable iTerm Settings > General > Magic > Python API, then run jvim .')
    print('First launch downloads plugins/tools. This installer does not run Git or open terminal windows.')
    print('iTerm may need restarting for its hyperlink underline setting. No restart is performed.')
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
