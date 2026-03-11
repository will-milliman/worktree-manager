<#
.SYNOPSIS
    Creates a git worktree for an Azure DevOps work item, sets up a virtual desktop,
    opens VS Code, launches Windows Terminal with split panes, and records session state.

.PARAMETER RepoPath
    Full path to the git repository (e.g. C:/Projects/rainier).

.PARAMETER RepoName
    Short name of the repository (e.g. rainier).

.PARAMETER BaseBranch
    The base branch to create the worktree from (e.g. main).

.PARAMETER BranchName
    The new branch name to create (e.g. task/88018/user-authentication).

.PARAMETER DesktopName
    Name for the virtual desktop (e.g. 88018-user-authentication).

.PARAMETER WorkItemId
    The Azure DevOps work item ID (e.g. 88018).

.PARAMETER WorkItemTitle
    The work item title (used in the Copilot prompt summary).

.PARAMETER WorkItemType
    The work item type (e.g. Task, Bug, User Story).

.PARAMETER WorkItemUrl
    The full URL to the Azure DevOps work item.

.PARAMETER RelativeWorkspacePath
    Path to the .code-workspace file relative to the worktree root
    (e.g. /monorepo/desktop/ui/.vscode/integrate.code-workspace).

.PARAMETER ProfileName
    The profile name from config/profiles.json (stored in sessions.json).

.PARAMETER CopilotPrompt
    Single-line prompt to pass to the first Copilot pane via -i.

.PARAMETER SetupCwd
    Optional relative path within the worktree to use as the CWD for the setup pane.

.PARAMETER SetupCommand
    Optional shell command to run in the bottom-left terminal pane (e.g. pnpm install).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $RepoPath,
    [Parameter(Mandatory = $true)]  [string] $RepoName,
    [Parameter(Mandatory = $true)]  [string] $BaseBranch,
    [Parameter(Mandatory = $true)]  [string] $BranchName,
    [Parameter(Mandatory = $true)]  [string] $DesktopName,
    [Parameter(Mandatory = $true)]  [int]    $WorkItemId,
    [Parameter(Mandatory = $true)]  [string] $WorkItemTitle,
    [Parameter(Mandatory = $true)]  [string] $WorkItemType,
    [Parameter(Mandatory = $true)]  [string] $WorkItemUrl,
    [Parameter(Mandatory = $true)]  [string] $RelativeWorkspacePath,
    [Parameter(Mandatory = $true)]  [string] $ProfileName,
    [Parameter(Mandatory = $true)]  [string] $CopilotPrompt,
    [Parameter(Mandatory = $false)] [string] $SetupCwd = "",
    [Parameter(Mandatory = $false)] [string] $SetupCommand = ""
)

$ErrorActionPreference = "Stop"
$pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"

# ── 1. Ensure VirtualDesktop module ───────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
    Install-Module VirtualDesktop -Scope CurrentUser -Force
}

# ── 2. Git setup and fetch ─────────────────────────────────────────────────────
Set-Location $RepoPath
git config core.longpaths true
git fetch origin $BaseBranch

# ── 3. Ensure .worktrees directory exists ──────────────────────────────────────
$worktreesRoot = "C:/Projects/worktree-manager/.worktrees"
if (-not (Test-Path $worktreesRoot)) {
    New-Item -ItemType Directory -Path $worktreesRoot -Force | Out-Null
}

# ── 4. Check for a parked worktree ────────────────────────────────────────────
# Use --porcelain output; normalize CRLF to LF before parsing
$worktreeList = (git worktree list --porcelain) -join "`n"
$worktreePath = $null

$entries = $worktreeList -split "\n\n"
foreach ($entry in $entries) {
    $lines = $entry.Trim() -split "\n" | ForEach-Object { $_.Trim() }
    $pathLine   = $lines | Where-Object { $_ -match '^worktree ' }
    $isDetached = $lines | Where-Object { $_ -match '^detached$' }
    if ($pathLine -and $isDetached) {
        $candidatePath = ($pathLine -replace '^worktree ', '').Trim()
        # Normalize path separators for comparison
        $normalizedCandidate = $candidatePath -replace '\\', '/'
        $normalizedRoot      = $worktreesRoot -replace '\\', '/'
        if ($normalizedCandidate -like "$normalizedRoot/*" -and $normalizedCandidate -match "$RepoName-\d+$") {
            $worktreePath = $candidatePath
            break
        }
    }
}

# ── 5a. Claim parked worktree (fast path) ─────────────────────────────────────
if ($worktreePath) {
    Write-Host "=== Claiming parked worktree: $worktreePath ==="
    Set-Location $worktreePath
    git reset --hard "origin/$BaseBranch"
    git checkout -b $BranchName
}
# ── 5b. Create new worktree (slow path) ───────────────────────────────────────
else {
    $existing = Get-ChildItem -Directory $worktreesRoot -Filter "$RepoName-*" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '-(\d+)$') { [int]$Matches[1] }
    }
    $nextIndex = if ($existing) { ($existing | Measure-Object -Maximum).Maximum + 1 } else { 1 }
    $worktreePath = "$worktreesRoot/$RepoName-$nextIndex"
    Write-Host "=== Creating new worktree: $worktreePath ==="
    Set-Location $RepoPath
    git worktree add -b $BranchName $worktreePath "origin/$BaseBranch"
    Write-Host "=== Verifying worktree ==="
    git worktree list
}

# ── 6. Create virtual desktop and open VS Code workspace ──────────────────────
Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
$workspacePath = "$worktreePath$RelativeWorkspacePath"
$desktop = New-WorktreeDesktop -Name $DesktopName
Switch-WorktreeDesktop -Desktop $desktop
Start-Process "code" -ArgumentList $workspacePath

# ── 7. Open Azure DevOps work item in browser ─────────────────────────────────
Start-Process $WorkItemUrl

# ── 8. Launch Windows Terminal with split panes ───────────────────────────────
$terminalCwd = if ($SetupCwd) { "$worktreePath$SetupCwd" } else { $worktreePath }
$logDir1 = "C:/Projects/worktree-manager/.sessions/logs/$WorkItemId-1"
$logDir2 = "C:/Projects/worktree-manager/.sessions/logs/$WorkItemId-2"
New-Item -ItemType Directory -Path $logDir1 -Force | Out-Null
New-Item -ItemType Directory -Path $logDir2 -Force | Out-Null

# Sanitize prompt — remove backticks and escape single quotes (used as delimiters in -Command)
$safeCopilotPrompt = $CopilotPrompt -replace '`', '' -replace "'", ''

$hasSetup = $SetupCommand -ne ""

if ($hasSetup) {
    # 1. copilot1 full → 2. split-V for copilot2 → 3. move left to copilot1 → 4. split-H for setup
    # → 5. move up to copilot1 → 6. move right to copilot2 → 7. split-H for git status
    wt -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoLogo -NoExit -Command "copilot -i '$safeCopilotPrompt' --model claude-opus-4.6 --log-dir '$logDir1'" `
      `; split-pane -V --size 0.5 -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoLogo -NoExit -Command "copilot --log-dir '$logDir2'" `
      `; move-focus left `
      `; split-pane -H --size 0.25 -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoExit -Command $SetupCommand `
      `; move-focus up `
      `; move-focus right `
      `; split-pane -H --size 0.25 -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoExit -Command "git status"
} else {
    wt -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoLogo -NoExit -Command "copilot -i '$safeCopilotPrompt' --model claude-opus-4.6 --log-dir '$logDir1'" `
      `; split-pane -V --size 0.5 -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoLogo -NoExit -Command "copilot --log-dir '$logDir2'" `
      `; split-pane -H --size 0.25 -p "Worktree" -d $terminalCwd `
        -- $pwsh -NoExit -Command "git status"
}

Write-Host "=== Windows Terminal launched ==="

# ── 9. Harvest Copilot session IDs from log files ────────────────────────────
Write-Host "Waiting for Copilot to initialize..."

function Get-CopilotSessionId([string]$logDir) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Start-Sleep -Seconds 10
        $files = Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending
        foreach ($file in $files) {
            $raw = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $raw) { continue }
            try {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
                $id = $json.sessionId ?? $json.session_id ?? $json.id ?? $json.session
                if ($id) { return $id }
            } catch {}
            if ($raw -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') {
                return $Matches[0]
            }
            if ($raw -match '"(?:sessionId|session_id|id)"\s*:\s*"([A-Za-z0-9_\-]{16,64})"') {
                return $Matches[1]
            }
        }
    }
    return $null
}

$sessionId1 = Get-CopilotSessionId $logDir1
$sessionId2 = Get-CopilotSessionId $logDir2

if (-not $sessionId1) { Write-Warning "Could not extract session ID from log dir 1: $logDir1" }
if (-not $sessionId2) { Write-Warning "Could not extract session ID from log dir 2: $logDir2" }
Write-Host "Session IDs: $sessionId1 | $sessionId2"

# ── 10. Update .sessions/sessions.json ────────────────────────────────────────
$sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
$sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
$sessionEntry = [PSCustomObject]@{
    worktreePath    = $worktreePath
    branch          = $BranchName
    desktopName     = $DesktopName
    profile         = $ProfileName
    workItemUrl     = $WorkItemUrl
    copilotSessions = @($sessionId1, $sessionId2) | Where-Object { $_ }
}
$sessions | Add-Member -NotePropertyName "$WorkItemId" -NotePropertyValue $sessionEntry -Force
$sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
Write-Host "Updated .sessions/sessions.json for task $WorkItemId"

# ── 11. Update status.json ────────────────────────────────────────────────────
$statusFile = "C:/Projects/worktree-manager/status.json"
$status = Get-Content $statusFile -Raw | ConvertFrom-Json
$worktreeName = Split-Path $worktreePath -Leaf
$status | Add-Member -NotePropertyName $worktreeName -NotePropertyValue $BranchName -Force
$status | ConvertTo-Json | Set-Content $statusFile
Write-Host "Updated status.json: $worktreeName = $BranchName"

Write-Host "=== Done! Worktree ready at $worktreePath ==="

