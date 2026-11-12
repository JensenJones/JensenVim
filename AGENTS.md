# Working preferences

- After requested changes, run appropriate checks, commit the changes and push the current branch to its configured upstream automatically.
- The user authorizes routine Git reads, commits and non-forced pushes for this repository. Preserve unrelated user changes and do not include them in commits.
- Ask before forced pushes, destructive operations or changes to unrelated repositories.

# Setting up jvim on a new machine

When asked to set up or check jvim on a new computer, follow the README section for the operating system, then verify it:

1. Print any `sudo` commands from the README for the user to run; do not run them yourself. Everything else (bootstrap line, installer) runs without a password.
2. On Linux, run `integrations/linux/desktop-keys.py`. If it lists clashes, explain them and run it with `--apply` once the user agrees.
3. Install the pinned plugins without a UI: `jvim --headless "+Lazy! restore" +qa`.
4. Run `python3 scripts/check.py` from the checkout (use `xvfb-run python3 scripts/check.py` when there is no display, for example over SSH). Skips are expected and explained in its output; failures are not.
5. For each failure, find the cause on this machine (missing package, desktop shortcut, terminal, path) and fix it, in the machine setup or in this repository. Rerun the check until it passes, then add a short dated result for this platform to `docs/VALIDATION.md`, commit and push.
6. Finish by asking the user to open WezTerm, run `jvim .`, and try Ctrl+S, Ctrl+W, Ctrl+Shift+A and paste, since the check cannot press keys in a real window.
