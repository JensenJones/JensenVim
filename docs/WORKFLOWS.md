# Project workflows

Open **Cmd+Shift+A** to search actions. File lookup is **Cmd+Shift+O**. **F4** toggles the project tree. The status line offers clickable Fold, Run and Config controls.

## Run configurations

Choose **Edit run configurations** to open `.jvim/run.json` in your project. Add configurations, save, then use **Choose run configuration** or click **Config**. Click **Run** to run the selected configuration in a terminal split.

```json
{
  "version": 1,
  "configurations": [
    { "name": "Build", "command": ["make"], "cwd": "." },
    { "name": "Tests", "command": ["make", "test-all"], "cwd": "." },
    {
      "name": "Program",
      "command": ["./build/program", "--verbose"],
      "cwd": ".",
      "env": { "LOG_LEVEL": "debug" }
    }
  ]
}
```

Commands are argument arrays. Paths containing spaces remain single arguments. Relative working directories resolve against the project; environment entries override inherited values. Configuration names must be unique. Configurations are loaded only for an explicit run/selection action; opening a repository never runs them.

A running configuration reopens its existing terminal. Completed output is retained. **Rerun selected configuration** starts it again; **Stop run** stops it; **Show run output** reopens the split. **Cmd+W** hides the terminal without killing the process. For shell features such as pipes, explicitly use a shell command array, for example `["sh", "-c", "make && ./build/program"]`.

**Cmd+Option+semicolon** opens/reuses an interactive project shell. Shells and run output accept ordinary terminal input. Project discovery prefers an ancestor `.jvim/run.json`, then common project markers, then the current working directory.

## Merge conflicts

Open a file containing conflict markers, then choose **Resolve merge conflicts**. jvim uses native diff panes: read-only Ours/Theirs previews, an optional Base preview for diff3 markers, and your editable result buffer.

Click the result's **Ours**, **Theirs**, **Both** or **Base** controls to resolve the current conflict. **Previous** and **Next** move between conflicts. Each acceptance is one undo step. You can also edit the result directly; conflict locations are recalculated before acceptance. Closing previews leaves your result available.

Both ordinary `<<<<<<<`/`=======`/`>>>>>>>` and diff3 `|||||||` markers are supported. Malformed or nested markers are rejected. The resolver does not run Git, stage files or write files itself; the normal standalone autosave policy still applies to edits. Review the result and use your usual Git workflow to stage it.

## Tree operations

Click a file once to open it. **Cmd+N** creates a file beside the selected file or inside the selected folder, even when the editor currently has focus. The action picker also offers **Focus project tree** and **New folder in project tree**.

For several files, focus the tree, move to each entry and use Neo-tree's **Mark tree files for moving** action (`x`) to collect cut entries. Select the destination folder and use **Move marked files into tree folder** (`p`). Existing Neo-tree prompts handle conflicts. Backspace/Delete are disabled in the tree so they cannot unexpectedly change its root. Use Neo-tree's `d` command to delete an entry with confirmation.

## C++ assistance

Provide a current `compile_commands.json` covering production and test translation units. clangd supplies suggestions, includes, navigation, rename and diagnostics. Use **Shift+F6** to rename; typing over a declaration cannot update references.

Some dependent template references are outside clangd's rename support. After a rename, jvim runs asynchronous syntax-only compiler checks from the compilation database and reports errors in the editor. **Check C++ project (syntax only)** runs the same check manually. It does not link or execute your program. Uninstantiated templates can still need review.

Formatting uses Conform and clang-format rather than custom Enter-alignment rules. Keep project style in `.clang-format`. Autosave preserves undo without reformatting; explicit saves and **Format file** apply formatting and include organisation.
