---
argument-hint: "<work-item-id> — e.g. 88018"
---

# Create Worktree from Azure DevOps Work Item

You are helping to create a git worktree based on an Azure DevOps work item.

## Input

The user provides a **work item ID** as free-text after the slash command.

- Parse the numeric value as the **work item ID** (required).
- Example: `/create-worktree 88018`

## Instructions

0.  **Interactive Configuration**

    Before doing any work, gather configuration choices interactively.

    First, read `config/profiles.json` to discover available profiles.

    Then, resolve the profile:
    - **Profile** _(only if multiple profiles exist)_: Use `ask_questions` to present a single-select picker from the profile names found in the config file.
      - If only **one profile** exists, skip this question — auto-select it and tell the user which profile was chosen.

    Store the resolved **profile** for use in subsequent steps.

## Steps

1.  **Load Configuration & Fetch Work Item**

    Run **all** of the following **in parallel** (they have no dependencies on each other):
    - **Resolve profile**: Using the profile selected in step 0 (either auto-selected or chosen by the user), extract the matching profile's repo path, base branch, workspace path, and `setup` config (if present).
      - Derive `<repo-name>` from the profile's repo path (last path segment, e.g., `C:/Projects/rainier` → `rainier`).
    - **Fetch work item**: Use `mcp_ado_wit_get_work_item` to fetch the work item.
      - Parameters:
        - id: the work item ID from user input
        - project: 'Rainier'
      - Extract:
        - Work item type (System.WorkItemType)
        - Title (System.Title)
        - Description (System.Description)

    Validate the profile exists and the work item is accessible before proceeding.

2.  **Generate Branch Name**
    - Format: `(task|bug)/<task-number>/<two-keywords>`
    - Branch prefix: 'task' for Task/User Story/Feature, 'bug' for Bug
    - Extract 2 meaningful keywords from title and description:
      - Filter out common words (the, a, an, and, or, is, are, etc.)
      - Prioritize words from title over description
      - Use words with 3+ characters
      - Join with hyphen (e.g., 'user-authentication')
    - Example: `task/88888/user-authentication`
    - **Check for existing branch**: After generating the branch name, verify it doesn't already exist locally or on remote:
      ```powershell
      git branch -a --list "*<branch-name>*"
      ```
    - If the branch already exists, pick a different pair of keywords from the title/description and regenerate the branch name. Repeat until a unique name is found.
    - When selecting alternative keywords, draw from the remaining unused meaningful words in the title first, then the description. Avoid reusing any keyword pair that was already attempted.

3.  **Provision Worktree (Claim or Create)**

    First, check if a **parked worktree** is available to reuse. A parked worktree is one with a `detached` HEAD (no `branch` line) in the output of `git worktree list --porcelain`, located under `C:/Projects/worktree-manager/.worktrees/<repo-name>-*`.

    **IMPORTANT — Single execution**: All sub-steps below MUST be run in a **single terminal command** to avoid unnecessary round-trips. Do NOT split these into separate `run_in_terminal` calls.

    ```powershell
    # Ensure VirtualDesktop module is installed
    if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
        Install-Module VirtualDesktop -Scope CurrentUser -Force
    }
    cd <repo-path>
    git config core.longpaths true
    git fetch origin <base-branch>
    if (-not (Test-Path "C:/Projects/worktree-manager/.worktrees")) {
        New-Item -ItemType Directory -Path "C:/Projects/worktree-manager/.worktrees" -Force | Out-Null
    }
    # Check for parked worktrees
    git worktree list --porcelain
    ```

    Parse the output to find parked worktrees (entries with `detached` and path matching `.worktrees/<repo-name>-*`).

    ### 3a. Claim a Parked Worktree _(fast path)_

    If a parked worktree is found, claim it by creating a new branch inside it. No directory move or rename is needed.

    ```powershell
    cd "<parked-worktree-path>"
    git reset --hard origin/<base-branch>
    git checkout -b <branch-name>
    ```

    The worktree path stays the same (e.g., `C:/Projects/worktree-manager/.worktrees/rainier-1`).

    ### 3b. Create a New Worktree _(slow path — only when no parked worktree is available)_

    Determine the next worktree index by scanning existing `<repo-name>-*` directories under `.worktrees/`:

    ```powershell
    # Find next available index
    $existing = Get-ChildItem -Directory "C:/Projects/worktree-manager/.worktrees" -Filter "<repo-name>-*" | ForEach-Object {
        if ($_.Name -match '-(\d+)$') { [int]$Matches[1] }
    }
    $nextIndex = if ($existing) { ($existing | Measure-Object -Maximum).Maximum + 1 } else { 1 }
    $worktreePath = "C:/Projects/worktree-manager/.worktrees/<repo-name>-$nextIndex"
    ```

    Then create the worktree using `origin/<base-branch>` as the start point:
    - Worktree location: `C:/Projects/worktree-manager/.worktrees/<repo-name>-<index>`
    - Execute: `git worktree add -b <branch-name> <worktree-path> origin/<base-branch>`
    - **Long-running command handling**: This can take a long time on large repositories (e.g., 35K+ files):
      1. Run the command as a **background terminal** (`isBackground=true`)
      2. Use `await_terminal` with the returned terminal ID and a generous timeout (e.g., 300000ms / 5 minutes)
      3. **Do NOT proceed** to step 4 until `await_terminal` returns a successful exit code
      4. After completion, verify the worktree was registered: `git worktree list`

4.  **Create Virtual Desktop and Open Workspace**
    - Construct the full workspace path by combining:
      - Worktree path (from step 3a or 3b)
      - Relative workspace path from profile config
      - Example: `<worktree-path>/<workspace-path-from-profile>`
    - Create a new virtual desktop named `<task-number>-<two-keywords>` (using the same keywords from the branch name):
      ```powershell
      Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
      $workspacePath = "<worktree-path>/<workspace-path-from-profile>"
      $desktop = New-WorktreeDesktop -Name "<task-number>-<two-keywords>"
      Switch-WorktreeDesktop -Desktop $desktop
      Start-Process "code" -ArgumentList $workspacePath
      ```

5.  **Open Azure DevOps Work Item in Browser**

    Since the work item was already fetched in step 1, extract the work item URL from the response (the `_links.html.href` field) and open it in the default browser:

    ```powershell
    Start-Process "<work-item-url>"
    ```

    If the URL was not available in the response, construct a fallback URL and open it anyway:

    ```powershell
    Start-Process "https://dev.azure.com/mgalfadev/5d438345-7020-4631-a370-020f9319088b/_workitems/edit/<task-number>"
    ```

6.  **Generate Work Item Context File**

    Write a `.github/copilot-instructions.md` file into the worktree so that VS Code Chat automatically loads the work item context into every conversation.

    > **IMPORTANT**: Use a **terminal command** (not a file-edit tool) to write this file, so it's created immediately without requiring user review.

    ```powershell
    $contextDir = "<worktree-path>/.github"
    if (-not (Test-Path $contextDir)) {
        New-Item -ItemType Directory -Path $contextDir -Force | Out-Null
    }

    $contextContent = @"
    # Active Work Item

    - **Type**: <work-item-type>
    - **ID**: <task-number>
    - **Title**: <title>
    - **URL**: <work-item-url>
    - **Branch**: <branch-name>

    ## Description

    <full-description-from-ado>
    "@

    Set-Content -Path "$contextDir/copilot-instructions.md" -Value $contextContent -Encoding UTF8
    Write-Host "Created .github/copilot-instructions.md with work item context"
    ```

    This file is untracked by git and will be automatically included in every VS Code Chat interaction within the worktree workspace. It is cleaned up automatically when the worktree is parked via `/clean-worktree` (since `git clean -fd` removes untracked files).

7.  **Setup Worktree for Development** _(skip if profile has no `setup` config)_

    If the resolved profile contains a `setup` object, run the setup command to prepare the worktree for development.
    - **Working directory**: `<worktree-path>` + `setup.cwd` (if specified). If `setup.cwd` is omitted, use the worktree root.
    - **Command**: `setup.command` — the raw shell command string from the profile.
    - **Visibility**: The terminal **must be visible** so the user can observe progress while they wait.

    > **CRITICAL**: Use `isBackground=false` — this is what makes the terminal visible.
    > `isBackground=true` creates an invisible background shell the user cannot see.
    > `isBackground=false` uses a shared, visible terminal that the user can watch in real-time.
    - **Long-running command handling**: Setup commands like `yarn install; yarn build` can take a long time:
      1. Run with `isBackground=false` and a generous `timeout` (e.g., 600000ms / 10 minutes)
      2. The tool call blocks until the command finishes (or times out), returning the exit code
      3. If the exit code is non-zero, stop and report the error

    ```powershell
    cd "<worktree-path>/<setup-cwd>"
    <setup-command>
    ```

8.  **Update Worktree Status File**

    Update `C:/Projects/worktree-manager/status.json` to record that this worktree is now in use with the new branch.

    The file is a JSON object where keys are worktree directory names (e.g., `rainier-1`) and values are the branch name (`"main"` when parked, the full branch name when in use). Ignore any entries not matching `<repo-name>-*` (e.g., `IDM`).

    > **IMPORTANT**: `status.json` is gitignored. Always update it via a **terminal command** (not a file-edit tool) so the change applies immediately without requiring user review.

    Read the current file, update the entry for the claimed/created worktree directory, and write it back:

    ```powershell
    $statusFile = "C:/Projects/worktree-manager/status.json"
    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
    $worktreeName = Split-Path "<worktree-path>" -Leaf   # e.g., "rainier-1"
    $status.$worktreeName = "<branch-name>"
    $status | ConvertTo-Json | Set-Content $statusFile
    ```

## Example Usage

```
/create-worktree 88018
```

The prompt will:

1. Ask the user to select a profile (if multiple exist)
2. Fetch work item 88018 from Azure DevOps
3. Create branch like `task/88018/implement-feature`
4. Claim a parked worktree (fast) or create a new one at `.worktrees/rainier-N` (slow)
5. Open the configured workspace on a new virtual desktop (`88018-implement-feature`)
6. Open the Azure DevOps work item in the browser
7. Generate `.github/copilot-instructions.md` in the worktree with work item context for VS Code Chat
8. Run the profile's setup command (e.g. `pnpm install`) if configured
9. Update `status.json` to record the worktree is in use with the new branch name

## Error Handling

- Verify work item exists and is accessible
- Ensure git repository is valid
- Handle git worktree creation failures
