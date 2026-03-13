<#
.SYNOPSIS
    Creates a git worktree for an Azure DevOps work item, sets up a virtual desktop,
    opens VS Code, and records session state.

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
    The work item title.

.PARAMETER WorkItemType
    The work item type (e.g. Task, Bug, User Story).

.PARAMETER WorkItemUrl
    The full URL to the Azure DevOps work item.

.PARAMETER RelativeWorkspacePath
    Path to the .code-workspace file relative to the worktree root
    (e.g. /monorepo/desktop/ui/.vscode/integrate.code-workspace).

.PARAMETER ProfileName
    The profile name from config/profiles.json (stored in sessions.json).

.PARAMETER SetupCwd
    Optional relative path within the worktree to use as the CWD for the setup command.

.PARAMETER SetupCommand
    Optional shell command to run after worktree creation (e.g. pnpm install).

.PARAMETER TerminalCwd
    Optional relative path within the worktree to open Windows Terminal in.

.PARAMETER TerminalCommand
    Optional command to run in the Windows Terminal tab (e.g. opencode).

.PARAMETER TerminalProfile
    Optional Windows Terminal profile name to use (e.g. Worktree).
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
    [Parameter(Mandatory = $false)] [string] $SetupCwd = "",
    [Parameter(Mandatory = $false)] [string] $SetupCommand = "",
    [Parameter(Mandatory = $false)] [string] $TerminalCwd = "",
    [Parameter(Mandatory = $false)] [string] $TerminalCommand = "",
    [Parameter(Mandatory = $false)] [string] $TerminalProfile = ""
)

$ErrorActionPreference = "Stop"

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
$workspacePath = Join-Path $worktreePath $RelativeWorkspacePath
$desktop = New-WorktreeDesktop -Name $DesktopName
Switch-WorktreeDesktop -Desktop $desktop
Start-Process "code" -ArgumentList $workspacePath

# ── 7. Open Azure DevOps work item in browser ─────────────────────────────────
Start-Process $WorkItemUrl

# ── 8. Open Windows Terminal (if configured) ──────────────────────────────────
if ($TerminalCommand -ne "") {
    $terminalDir = if ($TerminalCwd) { Join-Path $worktreePath $TerminalCwd } else { $worktreePath }
    $profileArg = if ($TerminalProfile) { " --profile `"$TerminalProfile`"" } else { "" }
    # First tab: terminal command (e.g. opencode)
    $wtArgs = "-d `"$terminalDir`"$profileArg pwsh -NoExit -Command `"$TerminalCommand`""
    # Second tab: setup command (if configured)
    if ($SetupCommand -ne "") {
        $setupDir = if ($SetupCwd) { Join-Path $worktreePath $SetupCwd } else { $worktreePath }
        $wtArgs += " ; new-tab -d `"$setupDir`"$profileArg pwsh -NoExit -Command `"$SetupCommand`""
    }
    Write-Host "=== Opening Windows Terminal ==="
    Start-Process "wt" -ArgumentList $wtArgs
}

# ── 9. Update .sessions/sessions.json ─────────────────────────────────────────
$sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
$sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
$sessionEntry = [PSCustomObject]@{
    worktreePath    = $worktreePath
    branch          = $BranchName
    desktopName     = $DesktopName
    profile         = $ProfileName
    workItemUrl     = $WorkItemUrl
}
$sessions | Add-Member -NotePropertyName "$WorkItemId" -NotePropertyValue $sessionEntry -Force
$sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
Write-Host "Updated .sessions/sessions.json for task $WorkItemId"

# ── 10. Update status.json ────────────────────────────────────────────────────
$statusFile = "C:/Projects/worktree-manager/status.json"
$status = Get-Content $statusFile -Raw | ConvertFrom-Json
$worktreeName = Split-Path $worktreePath -Leaf
$status | Add-Member -NotePropertyName $worktreeName -NotePropertyValue $BranchName -Force
$status | ConvertTo-Json | Set-Content $statusFile
Write-Host "Updated status.json: $worktreeName = $BranchName"

Write-Host "=== Done! Worktree ready at $worktreePath ==="

