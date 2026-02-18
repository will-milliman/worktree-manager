---
argument-hint: "<task-number> — or leave blank to list active worktrees"
---

# Clean Worktree (Park for Reuse)

Park a worktree so it can be reused by a future `/create-worktree` invocation. This closes the virtual desktop, resets the worktree to its base branch in a detached HEAD state, and deletes the old task branch — but **preserves the worktree directory and `node_modules`** so the next task gets a fast start.

## Input

The user provides an optional **task number** as free-text after the slash command.

- `/clean-worktree 88018` — park the worktree for task 88018
- `/clean-worktree` — list active worktrees and ask the user to pick one

### Auto-discovery (no task number provided)

If the user does not supply a task number, discover active (in-use) worktrees by checking which ones have a branch checked out:

```powershell
cd <repo-path>
git worktree list --porcelain
```

Parse the output and find worktrees under `C:/Projects/worktree-manager/.worktrees/` that have a `branch` line (not `detached`). Present them as a numbered list showing the worktree directory name and branch, and ask the user which one to clean up. If there are no active worktrees, inform the user and stop.

To determine `<repo-path>`, read `config/profiles.json` and extract the repo path. If there is only one profile, use it automatically. If multiple, list them and ask the user to choose.

## Instructions

1. **Close All Windows on Virtual Desktop and Remove It**

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   Close-AllWindowsOnDesktop -TaskNumber <task-number>
   ```

2. **Park the Worktree**

   First, identify which worktree directory contains the task's branch. Parse `git worktree list --porcelain` to find the entry whose `branch` line contains the task number (e.g., `branch refs/heads/task/88018/remove-prettier`). Extract the worktree path from that entry.

   Read `config/profiles.json` to determine the base branch for the profile (e.g., `master`).

   **IMPORTANT — Single execution**: All sub-steps below MUST be run in a **single terminal command**. Do NOT split these into separate `run_in_terminal` calls.

   ```powershell
   cd "<worktree-path>"

   # Fetch latest base branch
   git fetch origin <base-branch>

   # Discard all changes to tracked files
   git reset --hard origin/<base-branch>

   # Detach HEAD — this signals the worktree is "parked" and available for reuse
   git checkout --detach origin/<base-branch>

   # Remove untracked files but preserve .gitignore'd files (node_modules, .yarn, build caches)
   git clean -fd

   # Delete the old task branch (local only, never remote)
   git branch -D <old-branch-name>

   # Verify the worktree is now parked
   Write-Host "=== VERIFY ==="
   git worktree list --porcelain
   Write-Host "=== DONE ==="
   ```

   Verify that the worktree entry now shows `detached` instead of a `branch` line.

3. **Update Worktree Status File**

   Update `C:/Projects/worktree-manager/status.json` to record that this worktree is now parked.

   The file is a JSON object where keys are worktree directory names (e.g., `rainier-1`) and values are the branch name (`"main"` when parked, the full branch name when in use). Ignore any entries not matching `<repo-name>-*` (e.g., `IDM`).

   > **IMPORTANT**: `status.json` is gitignored. Always update it via a **terminal command** (not a file-edit tool) so the change applies immediately without requiring user review.

   Read the current file, set the entry for the parked worktree to `"main"`, and write it back:

   ```powershell
   $statusFile = "C:/Projects/worktree-manager/status.json"
   $status = Get-Content $statusFile -Raw | ConvertFrom-Json
   $worktreeName = Split-Path "<worktree-path>" -Leaf   # e.g., "rainier-1"
   $status.$worktreeName = "main"
   $status | ConvertTo-Json | Set-Content $statusFile
   ```

## Example Usage

```
/clean-worktree 88018
/clean-worktree
```

- With a task number: proceeds directly with parking.
- Without a task number: lists active worktrees and asks which to park.

Either form will:

1. Close all windows on the virtual desktop and remove it
2. Reset the worktree to the base branch, detach HEAD, clean untracked files, and delete the task branch
3. Update `status.json` to record the worktree is parked (set to `"main"`)
4. Leave the worktree directory intact with `node_modules` preserved for fast reuse

## Safety Notes

- Only local branches are deleted (never affects remote branches)
- If worktree has uncommitted changes, they will be lost — `git reset --hard` discards everything
- Consider pushing important work before parking
- `git clean -fd` removes untracked files but preserves `.gitignore`'d files like `node_modules`

## Error Handling

- If no virtual desktop is found for the task number, desktop cleanup is skipped automatically
- If some windows don't close within the timeout, desktop removal proceeds anyway (remaining windows move to adjacent desktop)
- If virtual desktop removal fails, continue with worktree parking
- If `git reset` or `git checkout --detach` fails, report the error to the user
- If the branch cannot be deleted (e.g., it doesn't exist), continue — this is non-fatal
