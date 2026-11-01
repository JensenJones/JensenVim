"""Run compilation-database commands in syntax-only mode; never build or run code."""
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys

SOURCE_SUFFIXES = {'.c', '.cc', '.cpp', '.cxx', '.c++', '.C', '.m', '.mm'}
DROP_FLAGS = {'-c', '-S', '-E', '-M', '-MM', '-MD', '-MMD', '-MP', '-MG', '-save-temps', '--save-temps', '-emit-ast', '-emit-pch', '-ftime-trace'}
DROP_VALUES = {'-o', '-MF', '-MT', '-MQ', '-MJ', '--output', '-serialize-diagnostics',
               '--serialize-diagnostics', '-serialize-diagnostic-file', '-dependency-file',
               '-fdiagnostics-serialization-file', '-foptimization-record-file'}
KEEP_VALUES = {'-I', '-isystem', '-iquote', '-idirafter', '-include', '-imacros', '-isysroot',
               '--sysroot', '-target', '--target', '-x', '-Xclang'}


def response_arguments(arguments, directory, depth=0):
    if depth > 10:
        raise ValueError('Compiler response files are nested too deeply')
    expanded = []
    for argument in arguments:
        if argument.startswith('@'):
            content = (directory/argument[1:]).read_text()
            expanded.extend(response_arguments(shlex.split(content), directory, depth + 1))
        else:
            expanded.append(argument)
    return expanded


def remove_outputs(arguments, preprocessor=False):
    kept, index = [], 0
    values = DROP_VALUES | ({'-MD', '-MMD'} if preprocessor else set())
    while index < len(arguments):
        argument = arguments[index]
        if argument == '-Xclang' and index + 1 < len(arguments):
            option = arguments[index + 1]
            if option in DROP_VALUES:
                index += 4 if arguments[index + 2:index + 3] == ['-Xclang'] else 3
                continue
            if option in DROP_FLAGS or any(option.startswith(flag + '=') for flag in DROP_VALUES):
                index += 2
                continue
            kept.extend(arguments[index:index + 2])
            index += 2
            continue
        if argument in values:
            index += 2
            continue
        if argument in DROP_FLAGS or any(argument.startswith(flag + '=') for flag in DROP_VALUES) or argument.startswith(('-MF', '-MT', '-MQ', '-MJ', '-save-temps=', '--save-temps=', '-ftime-trace=')):
            index += 1
            continue
        if argument.startswith('-o') and not argument.startswith(('-objc', '-object', '-openmp')):
            index += 1
            continue
        if argument.startswith('-Wp,'):
            options = remove_outputs(argument[4:].split(','), preprocessor=True)
            if options:
                kept.append('-Wp,' + ','.join(options))
        else:
            kept.append(argument)
        index += 1
    return kept


def compilation_commands(entries):
    """Split multi-source Make recipes into proper per-file compile commands."""
    commands, seen = [], set()
    for entry in entries:
        directory = Path(entry['directory']).resolve()
        arguments = entry.get('arguments') or shlex.split(entry['command'])
        if not arguments:
            continue
        arguments = [arguments[0]] + remove_outputs(response_arguments(arguments[1:], directory))
        kept, sources = [arguments[0]], []
        index = 1
        while index < len(arguments):
            argument = arguments[index]
            if argument in KEEP_VALUES:
                kept.extend(arguments[index:index + 2])
                index += 2
                continue
            if not argument.startswith('-') and Path(argument).suffix in SOURCE_SUFFIXES:
                sources.append(argument)
            else:
                kept.append(argument)
            index += 1
        for source in sources or [entry['file']]:
            filename = str((directory/source).resolve())
            key = (str(directory), tuple(kept + [filename]))
            if key not in seen:
                seen.add(key)
                commands.append({'directory': str(directory), 'file': filename,
                                 'arguments': kept + [filename]})
    return commands


def stop_process(process):
    def send(sig):
        try:
            if os.name == 'posix':
                os.killpg(process.pid, sig)
            else:
                process.send_signal(sig)
        except ProcessLookupError:
            pass

    send(signal.SIGTERM)
    try:
        process.communicate(timeout=0.5)
    except subprocess.TimeoutExpired:
        send(signal.SIGKILL)
        process.communicate(timeout=2)
    finally:
        # A wrapper can exit before descendants that no longer hold its pipes.
        if os.name == 'posix':
            send(signal.SIGKILL)


def check(database):
    result = {'checked': 0, 'failed': 0, 'output': '', 'errors': [], 'runs': []}
    active = None

    def cancel(*_):
        if active is not None:
            stop_process(active)
        raise SystemExit(130)

    signal.signal(signal.SIGTERM, cancel)
    commands = compilation_commands(json.loads(Path(database).read_text()))
    output = []
    for entry in commands:
        arguments = entry['arguments'] + ['-fsyntax-only', '-fdiagnostics-color=never']
        try:
            active = subprocess.Popen(arguments, cwd=entry['directory'], stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, start_new_session=os.name == 'posix')
            try:
                stdout, stderr = active.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                stop_process(active)
                result['errors'].append('Compiler check timed out: ' + entry['file'])
                continue
            result['checked'] += 1
            result['failed'] += active.returncode != 0
            diagnostic_output = '\n'.join(['Jvim checking directory: ' + entry['directory'], stderr, stdout, 'Jvim leaving directory'])
            output.append(diagnostic_output)
            result['runs'].append({'file': entry['file'], 'code': active.returncode, 'output': diagnostic_output})
        except OSError as error:
            result['errors'].append(str(error))
        finally:
            active = None
    result['output'] = '\n'.join(output)
    return result


if __name__ == '__main__':
    try:
        print(json.dumps(check(sys.argv[1])))
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({'checked': 0, 'failed': 0, 'output': '', 'errors': [str(error)], 'runs': []}))
