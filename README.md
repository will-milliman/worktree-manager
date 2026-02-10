# Worktree Manager

AI-powered Git worktree workflow for VS Code. Spins up isolated worktrees from Azure DevOps work items, each on its own Windows virtual desktop — and parks them for fast reuse when you're done.

## How It Works

Two Copilot slash commands handle the full lifecycle:

| Command | What it does |
|---|---|
| `/create-worktree <id> [profile]` | Fetches the ADO work item, creates a branch, provisions a worktree, opens a VS Code workspace on a new virtual desktop, and runs setup |
| `/clean-worktree [id]` | Closes all windows on the task's virtual desktop, resets the worktree to a detached HEAD, and deletes the local branch — but **keeps the directory and `node_modules`** so the next task starts fast |

### Worktree Reuse (Parking)

Cleaned worktrees aren't deleted. They stay on disk in a "parked" state (detached HEAD). The next `/create-worktree` reclaims a parked worktree instead of cloning from scratch, skipping the slow checkout on large repos.

## Setup

**Prerequisites:** PowerShell 5.1+, Git, [VirtualDesktop](https://www.powershellgallery.com/packages/VirtualDesktop) PS module.

```powershell
Install-Module VirtualDesktop -Scope CurrentUser
```

**Configuration:** Define repo profiles in [`config/profiles.json`](config/profiles.json):

```jsonc
{
  "integrate": {
    "repo": "C:/Projects/rainier",
    "branch": "main",
    "workspace": "/monorepo/desktop/ui/.vscode/integrate.code-workspace",
    "setup": {
      "cwd": "/monorepo/desktop/ui",
      "command": "yarn install; yarn build"
    }
  }
}
```

| Field | Description |
|---|---|
| `repo` | Absolute path to the main git repository |
| `branch` | Base branch for new worktrees |
| `workspace` | Relative path to the `.code-workspace` file opened in VS Code |
| `setup` | Optional install/build command run after worktree creation |

## Project Structure

```
config/profiles.json              # Repo profiles
scripts/VirtualDesktopManager.psm1 # Virtual desktop helpers (create, switch, close)
.github/prompts/                   # Copilot slash command definitions
  create-worktree.prompt.md
  clean-worktree.prompt.md
.worktrees/                        # Worktree directories (git-ignored)
```
