---
argument-hint: "<worktree-name>"
---

# Clean Worktree (Park for Reuse)

Park a worktree so it can be reused by a future `/create-worktree` invocation. This closes the virtual desktop and resets the worktree to its base branch in a detached HEAD state — but **preserves the worktree directory and `node_modules`** so the next task gets a fast start.

## Input

The user provides an optional **worktree name** (e.g., `rainier-2`) as free-text after the slash command.

- `/clean-worktree rainier-2` — park the worktree named `rainier-2`
- `/clean-worktree` — list active worktrees and ask the user to pick one

### Auto-discovery (no worktree name provided)

If the user does not supply a worktree name, discover active (in-use) worktrees from `status.json`:

1. Read `C:/Projects/worktree-manager/status.json`.
2. Filter entries where the value is **not** `"main"` (i.e., the worktree has an active branch).
3. If no active worktrees exist, inform the user and stop.
4. Use `ask_questions` to present a single-select picker:
   - **Question**: _"Which worktree do you want to clean?"_
   - **Options**: One per active worktree. Each option:
     - `label`: the worktree name (e.g., `rainier-1`)
     - `description`: the branch name (e.g., `task/88983/pnpm-install`)
5. Use the selected worktree name to proceed to step 1.

## Instructions

1. **Resolve Worktree Path and Task Number**

   Read `config/profiles.json` to determine the repo root path and base branch for the profile (e.g., `master`). The worktree directory path is `C:/Projects/worktree-manager/.worktrees/<worktree-name>` (e.g., `C:/Projects/worktree-manager/.worktrees/rainier-2`).

   Look up the branch name from `status.json` for the given worktree name. Extract the task number from the branch (e.g., `task/88018/remove-prettier` → `88018`).

2. **Close All Windows on Virtual Desktop and Remove It**

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   Close-AllWindowsOnDesktop -TaskNumber <task-number>
   ```

3. **Park the Worktree**

   **IMPORTANT — Single execution**: All sub-steps below MUST be run in a **single terminal command**. Do NOT split these into separate `run_in_terminal` calls.

   ```powershell
   Set-Location "<worktree-path>" -ErrorAction Stop

   # Safety guard — abort if we're not in the expected worktree directory
   $expectedPath = (Resolve-Path "<worktree-path>").Path
   $currentPath  = (Get-Location).Path
   if ($currentPath -ne $expectedPath) {
       Write-Error "ERROR: Expected to be in '$expectedPath' but current directory is '$currentPath'. Aborting to prevent data loss."
       exit 1
   }

   # Fetch latest base branch
   git fetch origin <base-branch>

   # Discard all changes to tracked files
   git reset --hard origin/<base-branch>

   # Detach HEAD — this signals the worktree is "parked" and available for reuse
   git checkout --detach origin/<base-branch>

   # Remove untracked files but preserve .gitignore'd files (node_modules, .yarn, build caches)
   git clean -fd

   # Verify the worktree is now parked
   Write-Host "=== VERIFY ==="
   git worktree list --porcelain
   Write-Host "=== DONE ==="
   ```

   Verify that the worktree entry now shows `detached` instead of a `branch` line.

4. **Remove Session Logs for the Task**

   Delete any `.sessions/logs` folders associated with the task number. These folders are named `<task-number>-<N>` (e.g., `90086-1`, `90086-2`).

   ```powershell
   $logsRoot = "C:/Projects/worktree-manager/.sessions/logs"
   Get-ChildItem -Path $logsRoot -Directory | Where-Object { $_.Name -match "^<task-number>-" } | ForEach-Object {
       Remove-Item -Recurse -Force $_.FullName
       Write-Host "Removed session log: $($_.FullName)"
   }
   ```

   If no matching folders exist, skip silently.

   Also remove the entry for the task number from `.sessions/sessions.json`:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
   $sessions.PSObject.Properties.Remove("<task-number>")
   $sessions | ConvertTo-Json -Depth 10 | Set-Content $sessionsFile
   ```

   If no entry exists for the task number, skip silently.

5. **Update Worktree Status File**

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
/clean-worktree rainier-2
/clean-worktree
```

- With a worktree name: proceeds directly with parking.
- Without a worktree name: lists active worktrees and asks which to park.

Either form will:

1. Close all windows on the virtual desktop and remove it
2. Reset the worktree to the base branch, detach HEAD, and clean untracked files
3. Remove `.sessions/logs/<task-number>-*` folders for the task
4. Update `status.json` to record the worktree is parked (set to `"main"`)
5. Leave the worktree directory intact with `node_modules` preserved for fast reuse

## Safety Notes

- If worktree has uncommitted changes, they will be lost — `git reset --hard` discards everything
- Consider pushing important work before parking
- `git clean -fd` removes untracked files but preserves `.gitignore`'d files like `node_modules`

## Error Handling

- If no virtual desktop is found for the task number, desktop cleanup is skipped automatically
- If some windows don't close within the timeout, desktop removal proceeds anyway (remaining windows move to adjacent desktop)
- If virtual desktop removal fails, continue with worktree parking
- If `git reset` or `git checkout --detach` fails, report the error to the user
