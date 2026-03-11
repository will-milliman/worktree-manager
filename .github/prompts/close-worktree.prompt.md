---
argument-hint: "<worktree-id>"
---

# Close Worktree (Suspend for Later)

Suspend a worktree by closing its virtual desktop and saving session metadata so it can be reopened later with `/open-worktree`. Unlike `/clean-worktree`, the git worktree is **left completely untouched** — the branch, working directory, and `node_modules` all stay exactly as they are. This is useful when you want to free up resources without losing any state.

## Input

The user provides an optional **worktree ID** as free-text after the slash command.

- `/close-worktree rainier-1` — close the worktree with ID `rainier-1`
- `/close-worktree` — list active worktrees and ask the user to pick one

### Auto-discovery (no worktree ID provided)

If the user does not supply a worktree ID, discover eligible worktrees from `status.json`:

1. Read `C:/Projects/worktree-manager/status.json`.
2. Filter entries where the value is **not** `"main"` (i.e., the worktree has an active branch).
3. Read `C:/Projects/worktree-manager/sessions.json` and **exclude** any entries whose worktree ID already appears as a key in `sessions.json` (these are already suspended).
4. If no eligible worktrees remain, inform the user and stop.
5. Use `ask_questions` to present a single-select picker:
   - **Question**: _"Which worktree do you want to close?"_
   - **Options**: One per eligible worktree. Each option:
     - `label`: the worktree ID (e.g., `rainier-1`)
     - `description`: the branch name (e.g., `task/88983/pnpm-install`)
6. Use the selected worktree ID to proceed to step 1.

## Instructions

1. **Identify Worktree and Branch**

   Look up the worktree ID in `status.json` to get the branch name.

   Derive the **repo name** directly from the worktree ID by stripping the trailing `-<number>` (e.g., `rainier-3` → repo name `rainier`). Then look up the matching profile in `config/profiles.json` — it's the profile whose `repo` path ends with that repo name. This gives you the **repo path** (e.g., `C:/Projects/rainier`).

   Run `git worktree list --porcelain` against **the profile's repo path** (not the worktree-manager directory):

   ```powershell
   git -C <repo-path> worktree list --porcelain
   ```

   Find the entry whose `worktree` path ends with the worktree ID (e.g., `.worktrees/rainier-3`). Extract:
   - The **worktree path** (from the `worktree` line)
   - The **full branch name** (from the `branch` line, stripping `refs/heads/`)
   - The **task number** from the branch name (e.g., `task/88018/remove-prettier` → `88018`)

   The **desktop name** for the session file should be derived from the branch name to match the convention used by `/create-worktree`: take the branch `task/<task-number>/<keywords>` and produce `<task-number>-<keywords>` (e.g., branch `task/88018/remove-prettier` → desktop name `88018-remove-prettier`). The actual desktop discovery and cleanup is handled internally by `Close-AllWindowsOnDesktop` in step 2 — do **not** manually enumerate desktops.

2. **Close All Windows on Virtual Desktop and Remove It**

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   Close-AllWindowsOnDesktop -TaskNumber <task-number>
   ```

   This finds the desktop by name prefix, sends `WM_CLOSE` to every window on it (including VS Code), waits up to 30 seconds for them to close, then removes the desktop. If no virtual desktop is found for the task number, the function skips cleanup automatically and logs a message. VS Code will save its session state automatically when it receives a graceful close.

## What This Does NOT Do

- **No git operations** — the worktree branch, working directory, uncommitted changes, and `node_modules` are all preserved exactly as-is.
- **No `status.json` changes** — the worktree remains recorded as in-use (the branch name stays).

## Example Usage

```
/close-worktree rainier-1
/close-worktree
```

Either form will:

1. Identify the worktree and its virtual desktop
2. Close all windows on the virtual desktop and remove it
3. Leave the git worktree completely untouched for later reopening with `/open-worktree`

## Error Handling

- If no virtual desktop is found for the task number, `Close-AllWindowsOnDesktop` skips desktop cleanup automatically
- If `Close-AllWindowsOnDesktop` fails, report the error to the user
- If some windows don't close within the timeout, desktop removal proceeds anyway (remaining windows move to adjacent desktop)
