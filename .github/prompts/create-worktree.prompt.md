---
argument-hint: "<work-item-id> [profile] — e.g. 88018 or 88018 integrate"
---

# Create Worktree from Azure DevOps Work Item

You are helping to create a git worktree based on an Azure DevOps work item.

## Input

The user provides a **work item ID** and an optional **profile name** as free-text after the slash command.

Parse the user's input:

- The numeric value is the **work item ID** (required).
- Any non-numeric word is the **profile name** (optional).
- Examples: `/create-worktree 88018`, `/create-worktree 88018 integrate`

## Instructions

1.  **Load Configuration & Fetch Work Item**

    Run **all** of the following **in parallel** (they have no dependencies on each other):
    - **Resolve profile**: Read `config/profiles.json`.
      - If the user specified a profile name, look it up.
      - If no profile was specified:
        - **One profile** → use it automatically (tell the user which was selected).
        - **Multiple profiles** → list them and ask the user to choose before proceeding.
      - Extract the matching profile's repo path, base branch, workspace path, and `setup` config (if present).
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

5.  **Setup Worktree for Development** _(skip if profile has no `setup` config)_

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

## Example Usage

```
/create-worktree 88888
/create-worktree 88888 integrate
```

Both forms will:

1. Auto-detect (or use the specified) profile and fetch work item 88888 (in parallel)
2. Create branch like `task/88888/implement-feature`
3. Claim a parked worktree (fast) or create a new one at `.worktrees/rainier-N` (slow)
4. Open the configured workspace on a new virtual desktop (`88888-implement-feature`)
5. Run the profile's setup command (e.g. `yarn install`) if configured — incremental when reusing

## Error Handling

- If the profile name is invalid, list available profiles and ask the user to pick one
- Verify work item exists and is accessible
- Ensure git repository is valid
- Handle git worktree creation failures
- Handle git worktree creation failures
