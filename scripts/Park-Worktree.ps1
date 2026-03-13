<#
.SYNOPSIS
    Parks a git worktree for reuse by resetting it to the base branch in a detached
    HEAD state, removing the session entry, and updating status.json.

.PARAMETER WorktreePath
    Full path to the worktree directory (e.g. C:/Projects/worktree-manager/.worktrees/rainier-2).

.PARAMETER BaseBranch
    The base branch to reset to (e.g. main).

.PARAMETER TaskNumber
    The Azure DevOps work item ID whose session entry should be removed (e.g. 90174).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $WorktreePath,
    [Parameter(Mandatory = $true)] [string] $BaseBranch,
    [Parameter(Mandatory = $true)] [string] $TaskNumber
)

$ErrorActionPreference = "Stop"

# ── 1. Safety guard ───────────────────────────────────────────────────────────
$expectedPath = (Resolve-Path $WorktreePath).Path
Set-Location $expectedPath
$currentPath = (Get-Location).Path
if ($currentPath -ne $expectedPath) {
    Write-Error "ERROR: Expected to be in '$expectedPath' but current directory is '$currentPath'. Aborting to prevent data loss."
    exit 1
}

# ── 2. Reset, detach, and clean ───────────────────────────────────────────────
Write-Host "=== Parking worktree: $WorktreePath ==="
git fetch origin $BaseBranch
git reset --hard "origin/$BaseBranch"
git checkout --detach "origin/$BaseBranch"
git clean -fd

# ── 3. Verify detached state ──────────────────────────────────────────────────
Write-Host "=== VERIFY ==="
git worktree list --porcelain
Write-Host "=== DONE ==="

# ── 4. Remove session entry from sessions.json ───────────────────────────────
$sessionsFile = "C:/Projects/worktree-manager/.sessions/sessions.json"
try {
    $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
    $sessions.PSObject.Properties.Remove($TaskNumber)
    $sessions | ConvertTo-Json -Depth 3 | Set-Content $sessionsFile
    Write-Host "Removed session entry for task $TaskNumber"
} catch {
    Write-Warning "Failed to update sessions.json: $_"
}

# ── 5. Update status.json ────────────────────────────────────────────────────
$statusFile = "C:/Projects/worktree-manager/status.json"
$status = Get-Content $statusFile -Raw | ConvertFrom-Json
$worktreeName = Split-Path $WorktreePath -Leaf
$status | Add-Member -NotePropertyName $worktreeName -NotePropertyValue "main" -Force
$status | ConvertTo-Json | Set-Content $statusFile
Write-Host "Updated status.json: $worktreeName = main"

Write-Host "=== Worktree $WorktreePath is now parked ==="
