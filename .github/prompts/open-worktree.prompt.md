---
argument-hint: "<task-number>"
---

# Open Worktree (Resume a Suspended Worktree)

Resume a worktree that was previously suspended with `/close-worktree`. This recreates the virtual desktop, reopens the VS Code workspace, and opens the Azure DevOps work item and GitHub pull request (if one exists) in the browser. The git worktree is already intact — no git operations are needed.

## Input

The user provides an optional **task number** as free-text after the slash command.

- `/open-worktree 88018` — reopen the worktree for task 88018
- `/open-worktree` — list closed worktrees and ask the user to pick one

### Auto-discovery (no task number provided)

If the user does not supply a task number, discover closed worktrees from `sessions.json`:

1. Read `C:/Projects/worktree-manager/sessions.json`.
2. If there are no entries (empty object), inform the user that there are no closed worktrees and stop.
3. Use `ask_questions` to present a single-select picker:
   - **Question**: _"Which worktree do you want to reopen?"_
   - **Options**: One per session entry. Each option:
     - `label`: the task number (the key in `sessions.json`, e.g., `88018`)
     - `description`: `<branch> (desktop: <desktopName>)` (e.g., `task/88018/remove-prettier (desktop: 88018-remove-prettier)`)
4. Use the selected task number to proceed to step 1.

## Instructions

1. **Load Session and Configuration**

   Read the session entry from `sessions.json` and the profile configuration:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
   $session = $sessions."<task-number>"
   ```

   If no entry exists for the task number, report the error and stop. If auto-discovery is available, list available sessions as a hint.

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

   Fetch the work item URL and open it in the default browser:

   ```powershell
   $taskNumber = <task-number>
   ```

   Use `mcp_ado_wit_get_work_item` to fetch the work item:
   - Parameters:
     - id: the task number from the session
     - project: `Rainier`
   - Extract the work item URL from the response (the `_links.html.href` field or `System.TeamProject` + id to construct it)
   - Open it in the default browser: `Start-Process "<work-item-url>"`

   If the work item cannot be fetched, construct a fallback URL and open it anyway:

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

5. **Remove Session Entry**

   Remove the task's entry from `sessions.json` to indicate the worktree is no longer suspended:

   ```powershell
   $sessionsFile = "C:/Projects/worktree-manager/sessions.json"
   $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
   $sessions.PSObject.Properties.Remove("<task-number>")
   $sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
   Write-Host "Session entry removed from sessions.json"
   ```

## Example Usage

```
/open-worktree 88018
/open-worktree
```

Either form will:

1. Load the saved session metadata from `sessions.json`
2. Create (or reuse) the virtual desktop with the original name and switch to it
3. Open the VS Code workspace (work item context is auto-loaded from `.github/copilot-instructions.md` in the worktree)
4. Open the Azure DevOps work item in the browser
5. Open the GitHub pull request in the browser (if one exists)
6. Remove the session entry from `sessions.json`

## Error Handling

- If no entry exists for the task number in `sessions.json`, report the error and list available sessions (if any)
- If `New-WorktreeDesktop` or `Switch-WorktreeDesktop` fails, report the error and stop
- If VS Code fails to launch, report the error but continue with browser steps
- If the Azure DevOps work item cannot be fetched, use the fallback URL
- If `gh` CLI is not installed or no PR exists, skip the PR step silently
- If `sessions.json` cannot be updated, warn the user but don't fail
