# Run Configuration Setup and Workspace Restore

## Goals

- Make the status-line **Config** action useful in a new repository without requiring the user to understand the JSON schema first.
- Let a named configuration run one command or a sequence of commands, with no shell quoting required for ordinary argument lists.
- Offer editable starter configurations for common project types.
- Ensure **Cmd+Shift+W** saves the active repository workspace, and launching jvim in that repository restores it.

## Current behavior

Run configurations live in `.jvim/run.json`. Each configuration has a name and one argv array in `command`, plus optional `cwd` and `env`. **Config** selects a configuration. If the file is missing, the action creates an empty file; the next selection reports “No run configurations” in red. Several commands require spelling out a shell invocation such as `sh -c`.

Workspace save currently derives its key from `getcwd()`. The project tree and active file can identify a repository different from the window's working directory, which can make close and relaunch use different session keys.

## Proposed behavior

Keep `.jvim/run.json` as the portable, editable source of truth. Preserve existing `command` entries. Add `steps`, an ordered list of argv arrays, to run several commands in sequence:

```json
{
  "version": 1,
  "configurations": [
    {
      "name": "Build and test",
      "steps": [
        ["cmake", "-S", ".", "-B", "build"],
        ["cmake", "--build", "build"],
        ["ctest", "--test-dir", "build", "--output-on-failure"]
      ],
      "cwd": "."
    }
  ]
}
```

When **Config** finds no file or an empty configuration list, open a setup picker with project-detected presets, **Custom command**, and **Edit JSON manually**. Choosing a preset writes an editable configuration into `.jvim/run.json` and opens it; it does not execute anything. Detect and offer Make, CMake, Python/pytest, Node/npm, and Rust/Cargo starters when their marker files exist. The user can edit names and commands before saving. The **Run** control remains the explicit execution action.

When one or more configurations exist, **Config** keeps selecting among them. Invalid JSON or invalid commands still show a red error with the file path and the specific field to fix; an empty configuration list is a setup state, not an error.

Run a configuration's steps in order in the existing jvim terminal pane, using argv directly. Stop on the first failed step and show its exit status. Rerun starts again from step one. A configuration with `command` continues to run as it does now.

For workspace sessions, resolve the root from the active project's tree/file context, with repository markers as fallback, rather than relying only on the process working directory. Save under that canonical root on **Cmd+Shift+W**. On startup without explicit file arguments, resolve the same root and restore its saved layout, pane-local tabs, cursor, and scroll views. Keep the existing unsaved-file confirmation behavior.

## Scope and compatibility

- Keep version 1 and all existing `command` configurations valid.
- Keep commands as argv arrays to preserve spaces and avoid shell-specific command quoting; shell commands remain available through explicit `sh -c` or platform shell use.
- Presets only write starter text; they never run commands during setup or project discovery.
- No new dependencies.

## Verification

- Missing and empty configuration flows open setup, not an error notification.
- Each preset creates valid editable JSON without executing its commands.
- A two-step configuration runs in order, stops on a failing step, and supports rerun.
- Existing single-command configurations and their environment, cwd, and argument behavior remain unchanged.
- The **Cmd+Shift+W** mapping writes a project-root session, and a fresh launch in that repository restores splits, pane tabs, and views; an explicit file launch bypasses restore.
