---
argument-hint: "<worktree-id>"
---

# Open Worktree (Resume a Suspended Worktree)

Resume a worktree that was previously suspended with `/close-worktree`. This recreates the virtual desktop, reopens the VS Code workspace, and opens the Azure DevOps work item and GitHub pull request (if one exists) in the browser. The git worktree is already intact — no git operations are needed.

## Input

The user provides an optional **worktree ID** as free-text after the slash command.

- `/open-worktree rainier-1` — reopen the worktree with ID `rainier-1`
- `/open-worktree` — list closed worktrees and ask the user to pick one

### Auto-discovery (no worktree ID provided)

If the user does not supply a worktree ID, discover closed worktrees from `sessions.json`:

1. Read `C:/Projects/worktree-manager/.sessions/sessions.json`.
2. If there are no entries (empty object), inform the user that there are no closed worktrees and stop.
3. Use `ask_questions` to present a single-select picker:
   - **Question**: _"Which worktree do you want to reopen?"_
   - **Options**: One per session entry. Each option:
     - `label`: the task number (the key in `sessions.json`, e.g., `90086`)
     - `description`: `<branch> (desktop: <desktopName>)` (e.g., `task/90086/filter-placeholder (desktop: 90086-filter-placeholder)`)
4. Derive the worktree ID from the selected session's `worktreePath` (last path segment, e.g. `rainier-3`) and proceed to step 1.

## Instructions

1. **Load Session and Configuration**

   Resolve the session key via `status.json` and read the session entry from `sessions.json`:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json

   # The session key is always the task number — resolve it from the branch in status.json.
   $status = Get-Content "C:/Projects/worktree-manager/status.json" -Raw | ConvertFrom-Json
   $branch = $status."<worktree-id>"
   if ($branch -match '^task/(\d+)/') {
       $sessionKey = $Matches[1]
   } else {
       Write-Error "No task branch found for worktree '<worktree-id>' in status.json (branch: $branch)"
       return
   }

   $session = $sessions."$sessionKey"
   ```

   If no entry exists for the resolved session key, report the error and stop. If auto-discovery is available, list available sessions as a hint.

   Read `config/profiles.json` and resolve the profile stored in `$session.profile`. Extract the `workspace` path from the profile to construct the full VS Code workspace path:

   ```
   <worktreePath><workspace-path-from-profile>
   ```

   For example: `C:/Projects/worktree-manager/.worktrees/rainier-2/monorepo/desktop/ui/.vscode/integrate.code-workspace`

2. **Create Virtual Desktop and Open VS Code Workspace**

   Recreate the virtual desktop with the same name it had before, switch to it, and open the VS Code workspace:

   ```powershell
   Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
   $workspacePath = "<worktree-path><workspace-path-from-profile>"
   $desktop = New-WorktreeDesktop -Name "<desktopName-from-session>"
   Switch-WorktreeDesktop -Desktop $desktop
   Start-Process "code" -ArgumentList $workspacePath
   ```

   `New-WorktreeDesktop` will return the existing desktop if one with that name already exists, or create a new one.

3. **Open Azure DevOps Work Item in Browser**

   Open the work item URL stored in the session directly in the default browser:

   ```powershell
   Start-Process $session.workItemUrl
   ```

   If `$session.workItemUrl` is missing or empty (older session entries may not have it), fall back to constructing the URL from the task number — extract it from the branch name (e.g., `task/88018/remove-prettier` → `88018`) and open:

   ```powershell
   Start-Process "https://dev.azure.com/mgalfadev/5d438345-7020-4631-a370-020f9319088b/_workitems/edit/<task-number>"
   ```

4. **Open GitHub Pull Request in Browser (if one exists)**

   From the worktree directory, use the GitHub CLI to find a PR for the branch:

   ```powershell
   cd "<worktree-path>"
   $prUrl = gh pr view --head "<branch-name>" --json url --jq ".url" 2>$null
   if ($prUrl) {
       Start-Process $prUrl
       Write-Host "Opened PR: $prUrl"
   } else {
       Write-Host "No pull request found for branch <branch-name>. Skipping."
   }
   ```

   If `gh` is not installed or no PR exists for the branch, skip this step silently and continue.

   Also extract `setup.cwd` from the profile (if present) — this is used in step 5 to determine the terminal CWD.

5. **Launch Windows Terminal**

   Derive the terminal CWD from the session's worktree path and the profile's `setup.cwd` (if present):

   ```powershell
   $pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
   $setupCwd = "<setup.cwd-from-profile>"  # empty string if not present
   $terminalCwd = if ($setupCwd) { "$($session.worktreePath)$setupCwd" } else { $session.worktreePath }
   ```

   Read the Copilot session IDs from `$session.copilotSessions` and build resume commands. If a session ID is available use `--resume`; otherwise fall back to a plain `copilot` invocation:

   ```powershell
   $sessionId1 = $session.copilotSessions[0]
   $sessionId2 = $session.copilotSessions[1]
   $copilotCmd1 = if ($sessionId1) { "copilot --resume $sessionId1" } else { "copilot" }
   $copilotCmd2 = if ($sessionId2) { "copilot --resume $sessionId2" } else { "copilot" }
   ```

   Launch Windows Terminal with the same 3-pane split layout used by `/create-worktree`:

   ```powershell
   wt -p "Worktree" -d $terminalCwd `
       -- $pwsh -NoLogo -NoExit -Command $copilotCmd1 `
     `; split-pane -V --size 0.5 -p "Worktree" -d $terminalCwd `
       -- $pwsh -NoLogo -NoExit -Command $copilotCmd2 `
     `; move-focus left `
     `; split-pane -H --size 0.25 -p "Worktree" -d $terminalCwd `
     `; move-focus up `
     `; move-focus right `
     `; split-pane -H --size 0.25 -p "Worktree" -d $terminalCwd `
       -- $pwsh -NoExit -Command "git status"
   ```

   This produces:
   - **Top-left**: Copilot session 1 (75% height) — resumed or fresh
   - **Bottom-left**: blank terminal (25% height)
   - **Top-right**: Copilot session 2 (75% height) — resumed or fresh
   - **Bottom-right**: `git status` (25% height)

6. **Remove Session Entry**

   Remove the worktree's entry from `sessions.json` to indicate it is no longer suspended:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
   $sessions.PSObject.Properties.Remove($sessionKey)
   $sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
   Write-Host "Session entry removed from sessions.json"
   ```

## Example Usage

```
/open-worktree rainier-1
/open-worktree
```

Either form will:

1. Load the saved session metadata from `sessions.json`
2. Create (or reuse) the virtual desktop with the original name and switch to it
3. Open the VS Code workspace (work item context is auto-loaded from `.github/copilot-instructions.md` in the worktree)
4. Open the Azure DevOps work item in the browser
5. Open the GitHub pull request in the browser (if one exists)
6. Launch Windows Terminal with 3 split panes resuming the saved Copilot sessions
7. Remove the session entry from `sessions.json`

## Error Handling

- If no entry exists for the worktree ID in `sessions.json`, report the error and list available sessions (if any)
- If `New-WorktreeDesktop` or `Switch-WorktreeDesktop` fails, report the error and stop
- If VS Code fails to launch, report the error but continue with browser steps
- If `$session.workItemUrl` is missing, construct the fallback URL from the branch name
- If `gh` CLI is not installed or no PR exists, skip the PR step silently
- If Windows Terminal fails to launch, report the error but continue to remove the session entry
- If `sessions.json` cannot be updated, warn the user but don't fail
