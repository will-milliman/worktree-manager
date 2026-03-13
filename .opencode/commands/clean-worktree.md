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

   Read `config/profiles.json` to determine the repo root path and base branch for the profile (e.g., `main`). The worktree directory path is `C:/Projects/worktree-manager/.worktrees/<worktree-name>` (e.g., `C:/Projects/worktree-manager/.worktrees/rainier-2`).

   Look up the branch name from `status.json` for the given worktree name. Extract the task number from the branch (e.g., `task/88018/remove-prettier` → `88018`).

2. **Close All Windows on Virtual Desktop and Remove It**

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   Close-AllWindowsOnDesktop -TaskNumber <task-number>
   ```

3. **Park the Worktree, Remove Session Entry, and Update Status**

   Run `Park-Worktree.ps1` as a **single terminal execution** via `pwsh -File`. This handles the git reset/detach/clean, removes the session entry from `sessions.json`, and updates `status.json` — all in one script invocation.

   **Important:** Always invoke via `pwsh -File` (not `-Command`) to avoid bash interpreting `$` variable sigils in the PowerShell code.

   ```
   pwsh -ExecutionPolicy Bypass -File C:/Projects/worktree-manager/scripts/Park-Worktree.ps1 -WorktreePath "<worktree-path>" -BaseBranch "<base-branch>" -TaskNumber <task-number>
   ```

   Verify in the output that the worktree entry now shows `detached` instead of a `branch` line.

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
3. Remove the session entry from `.sessions/sessions.json`
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
