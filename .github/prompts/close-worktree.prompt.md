---
argument-hint: "<task-number> — or leave blank to list active worktrees"
---

# Close Worktree (Suspend for Later)

Suspend a worktree by closing its virtual desktop and saving session metadata so it can be reopened later with `/open-worktree`. Unlike `/clean-worktree`, the git worktree is **left completely untouched** — the branch, working directory, and `node_modules` all stay exactly as they are. This is useful when you want to free up resources without losing any state.

## Input

The user provides an optional **task number** as free-text after the slash command.

- `/close-worktree 88018` — close the worktree for task 88018
- `/close-worktree` — list active worktrees and ask the user to pick one

### Auto-discovery (no task number provided)

If the user does not supply a task number, discover active (in-use) worktrees:

```powershell
cd <repo-path>
git worktree list --porcelain
```

Parse the output and find worktrees under `C:/Projects/worktree-manager/.worktrees/` that have a `branch` line (not `detached`). Then check which of those already have an entry in `C:/Projects/worktree-manager/sessions.json` (meaning they are already closed). **Exclude** any worktrees that already have a session entry.

Present the remaining active worktrees as a numbered list showing the worktree directory name and branch, and ask the user which one to close. If there are no eligible worktrees, inform the user and stop.

To determine `<repo-path>`, read `config/profiles.json` and extract the repo path. If there is only one profile, use it automatically. If multiple, list them and ask the user to choose.

## Instructions

1. **Identify Worktree and Branch**

   Parse `git worktree list --porcelain` to find the worktree entry whose `branch` line contains the task number (e.g., `branch refs/heads/task/88018/remove-prettier`). Extract:
   - The **worktree path** (from the `worktree` line)
   - The **full branch name** (from the `branch` line, stripping `refs/heads/`)

   Determine the matching **profile name** from `config/profiles.json` by deriving `<repo-name>` from the worktree path (e.g., the worktree path `.worktrees/rainier-1` → repo name is `rainier` → match the profile whose `repo` path ends with `rainier`).

   The **desktop name** for the session file should be derived from the branch name to match the convention used by `/create-worktree`: take the branch `task/<task-number>/<keywords>` and produce `<task-number>-<keywords>` (e.g., branch `task/88018/remove-prettier` → desktop name `88018-remove-prettier`). The actual desktop discovery and cleanup is handled internally by `Close-AllWindowsOnDesktop` in step 3 — do **not** manually enumerate desktops.

2. **Save Session Metadata**

   Add the session entry to `sessions.json`, keyed by task number:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json

   $session = @{
       desktopName  = "<desktop-name>"
       worktreePath = "<worktree-path>"
       branch       = "<branch-name>"
       profile      = "<profile-name>"
   }

   $sessions | Add-Member -NotePropertyName "<task-number>" -NotePropertyValue $session -Force
   $sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
   Write-Host "Session saved to sessions.json for task <task-number>"
   ```

   If a key for this task number already exists in `sessions.json`, warn the user and ask whether to overwrite. If they decline, stop.

3. **Close All Windows on Virtual Desktop and Remove It**

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   Close-AllWindowsOnDesktop -TaskNumber <task-number>
   ```

   This finds the desktop by name prefix, sends `WM_CLOSE` to every window on it (including VS Code), waits up to 30 seconds for them to close, then removes the desktop. If no virtual desktop is found for the task number, the function skips cleanup automatically and logs a message. VS Code will save its session state automatically when it receives a graceful close.

## What This Does NOT Do

- **No git operations** — the worktree branch, working directory, uncommitted changes, and `node_modules` are all preserved exactly as-is.
- **No `status.json` changes** — the worktree remains recorded as in-use (the branch name stays). The presence of an entry in `sessions.json` indicates the worktree is suspended.

## Example Usage

```
/close-worktree 88018
/close-worktree
```

Either form will:

1. Identify the worktree and its virtual desktop
2. Save session metadata to `sessions.json`
3. Close all windows on the virtual desktop and remove it
4. Leave the git worktree completely untouched for later reopening with `/open-worktree`

## Error Handling

- If no virtual desktop is found for the task number, `Close-AllWindowsOnDesktop` skips desktop cleanup automatically — the session entry is still saved
- If a session entry already exists for the task number, ask the user before overwriting
- If `Close-AllWindowsOnDesktop` fails, continue — the session metadata is already saved
- If some windows don't close within the timeout, desktop removal proceeds anyway (remaining windows move to adjacent desktop)
- If `sessions.json` cannot be written, report the error to the user
