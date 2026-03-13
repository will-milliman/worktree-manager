<#
.SYNOPSIS
    Reopens a previously suspended worktree by recreating its virtual desktop,
    launching VS Code, opening the Azure DevOps work item and GitHub PR (if any),
    and removing the session entry from sessions.json.

.PARAMETER WorktreePath
    Full path to the worktree directory (e.g. C:/Projects/worktree-manager/.worktrees/rainier-2).

.PARAMETER BranchName
    The branch checked out in the worktree (e.g. task/90149/update-header).

.PARAMETER DesktopName
    Name for the virtual desktop (e.g. 90149-update-header).

.PARAMETER SessionKey
    The session key in sessions.json (the task number, e.g. 90149).

.PARAMETER WorkItemUrl
    The full URL to the Azure DevOps work item.

.PARAMETER WorkspacePath
    Full path to the .code-workspace file
    (e.g. C:/Projects/worktree-manager/.worktrees/rainier-2/monorepo/desktop/ui/.vscode/integrate.code-workspace).

.PARAMETER TerminalDir
    Optional full path to the directory to open Windows Terminal in.

.PARAMETER TerminalCommand
    Optional command to run in the Windows Terminal tab (e.g. opencode).

.PARAMETER TerminalProfile
    Optional Windows Terminal profile name to use (e.g. Worktree).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $WorktreePath,
    [Parameter(Mandatory = $true)]  [string] $BranchName,
    [Parameter(Mandatory = $true)]  [string] $DesktopName,
    [Parameter(Mandatory = $true)]  [string] $SessionKey,
    [Parameter(Mandatory = $true)]  [string] $WorkItemUrl,
    [Parameter(Mandatory = $true)]  [string] $WorkspacePath,
    [Parameter(Mandatory = $false)] [string] $TerminalDir = "",
    [Parameter(Mandatory = $false)] [string] $TerminalCommand = "",
    [Parameter(Mandatory = $false)] [string] $TerminalProfile = ""
)

$ErrorActionPreference = "Stop"

# ── 1. Create virtual desktop and open VS Code workspace ──────────────────────
Import-Module C:/Projects/worktree-manager/scripts/VirtualDesktopManager.psm1
$desktop = New-WorktreeDesktop -Name $DesktopName
Switch-WorktreeDesktop -Desktop $desktop
Start-Process "code" -ArgumentList $WorkspacePath
Write-Host "Opened VS Code workspace on desktop $DesktopName"

# ── 2. Open Windows Terminal with command (if configured) ─────────────────────
if ($TerminalCommand -ne "") {
    $termDir = if ($TerminalDir) { $TerminalDir } else { $WorktreePath }
    $profileArg = if ($TerminalProfile) { " --profile `"$TerminalProfile`"" } else { "" }
    Write-Host "=== Opening Windows Terminal in $termDir ==="
    Start-Process "wt" -ArgumentList "-d `"$termDir`"$profileArg pwsh -NoExit -Command `"$TerminalCommand`""
}

# ── 3. Open Azure DevOps work item in browser ────────────────────────────────
Start-Process $WorkItemUrl
Write-Host "Opened work item in browser: $WorkItemUrl"

# ── 4. Open GitHub PR in browser (if one exists) ─────────────────────────────
try {
    Set-Location $WorktreePath
    $prUrl = & gh pr view --head $BranchName --json url --jq ".url" 2>$null
    if ($prUrl) {
        Start-Process $prUrl
        Write-Host "Opened PR: $prUrl"
    } else {
        Write-Host "No pull request found for branch $BranchName. Skipping."
    }
} catch {
    Write-Host "No pull request found for branch $BranchName. Skipping."
}

# ── 5. Remove session entry from sessions.json ───────────────────────────────
$sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
try {
    $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
    $sessions.PSObject.Properties.Remove($SessionKey)
    $sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
    Write-Host "Session entry removed from sessions.json"
} catch {
    Write-Warning "Failed to update sessions.json: $_"
}

Write-Host "=== Done! Worktree $WorktreePath reopened ==="
