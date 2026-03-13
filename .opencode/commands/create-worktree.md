---
argument-hint: "<work-item-id> — e.g. 88018"
---

# Create Worktree from Azure DevOps Work Item

You are helping to create a git worktree based on an Azure DevOps work item.

The flow has three phases:

1. **Gather all information** (parallel subtasks)
2. **Assemble script parameters** (present a summary)
3. **Run a single consolidated PowerShell script** (all mechanical work happens here)

Do not run any terminal commands or file operations until Phase 3.

## Input

The user provides a **work item ID** as free-text after the slash command.

- Parse the numeric value as the **work item ID** (required).
- Example: `/create-worktree 88018`

---

## Step 0 — Profile Selection (Interactive, Required Before Phase 1)

Read `config/profiles.json` to discover available profiles.

- If **multiple profiles** exist: use `ask_questions` to present a single-select picker from the profile names.
- If **one profile** exists: auto-select it and tell the user which profile was chosen.

Store the resolved **profile name** — all Phase 1 subtasks depend on it.

---

## Phase 1 — Gather Information (Parallel Subtasks)

Run **Subtask A** and **Subtask B** simultaneously. After both complete, run **Subtask C**.

### Subtask A — Resolve Profile Config

Using the profile selected in Step 0, extract the following from `config/profiles.json`:

| Variable                 | Source                                                                                   |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| `$repoPath`              | profile `repo` field (e.g. `C:/Projects/rainier`)                                        |
| `$repoName`              | last path segment of `$repoPath` (e.g. `rainier`)                                        |
| `$baseBranch`            | profile `branch` field (e.g. `main`)                                                     |
| `$relativeWorkspacePath` | profile `workspace` field (e.g. `/monorepo/desktop/ui/.vscode/integrate.code-workspace`) |
| `$hasSetup`              | `true` if profile has a `setup` object, otherwise `false`                                |
| `$setupCwd`              | `setup.cwd` if present (relative path, e.g. `/monorepo/desktop/ui`)                      |
| `$setupCommand`          | `setup.command` if present (e.g. `pnpm install`)                                         |
| `$hasTerminal`           | `true` if profile has a `terminal` object, otherwise `false`                             |
| `$terminalCwd`           | `terminal.cwd` if present (relative path, e.g. `/monorepo/desktop/ui`)                   |
| `$terminalCommand`       | `terminal.command` if present (e.g. `opencode`)                                          |
| `$terminalProfile`       | `terminal.profile` if present (e.g. `Worktree`)                                         |

### Subtask B — Fetch Work Item

Use `mcp_ado_wit_get_work_item` to fetch the work item:

- `id`: the work item ID from user input
- `project`: `Rainier`

Extract:

| Variable               | Source                                                   |
| ---------------------- | -------------------------------------------------------- |
| `$workItemType`        | `System.WorkItemType` (e.g. `Task`, `Bug`, `User Story`) |
| `$workItemTitle`       | `System.Title`                                           |
| `$workItemDescription` | `System.Description` (strip HTML tags for plain text)    |
| `$workItemUrl`         | `_links.html.href` from the response                     |

If `_links.html.href` is not present, construct the fallback URL:

```
https://dev.azure.com/mgalfadev/5d438345-7020-4631-a370-020f9319088b/_workitems/edit/<work-item-id>
```

### Subtask C — Generate & Validate Branch Name _(after A & B complete)_

**Generate branch name:**

- Format: `(task|bug)/<work-item-id>/<keyword1>-<keyword2>`
- Prefix: `task` for Task / User Story / Feature; `bug` for Bug
- Extract 2 meaningful keywords from title and description:
  - Filter out stopwords (the, a, an, and, or, is, are, in, on, for, to, of, with, etc.)
  - Prioritize words from the title over description
  - Use words with 3+ characters
  - Join with hyphen (e.g. `user-authentication`)
- Example: `task/88018/user-authentication`

**Validate uniqueness:**

Run the following terminal command to check if the branch already exists:

```powershell
git -C "<repoPath>" branch -a --list "*<branchName>*"
```

If output is non-empty, the branch already exists. Pick a different keyword pair from the remaining unused meaningful words (title first, then description) and retry. Continue until a unique name is found.

**Derive desktop name:**

- `$desktopName` = `<work-item-id>-<keyword1>-<keyword2>` (e.g. `88018-user-authentication`)

---

## Phase 2 — Parameter Summary

Before running anything, present the following summary so the user can see exactly what will happen:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Worktree Parameters
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Work Item:      #<workItemId> — <workItemTitle>
  Type:           <workItemType>
  Branch:         <branchName>
  Desktop:        <desktopName>
  Repo:           <repoPath>
  Base Branch:    <baseBranch>
  Workspace:      <repoPath><relativeWorkspacePath>
  Terminal CWD:   <repoPath><setupCwd>
  Setup Command:  <setupCommand> OR "(none)"
  Terminal:       <terminalCommand> in <terminalCwd> OR "(none)"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then proceed immediately to Phase 3 — do not ask for confirmation.

---

## Phase 3 — Run Consolidated Script

Call `scripts/Create-Worktree.ps1` as a **single terminal execution**, passing all values resolved in Phase 1 as named parameters.

**Important:** Always invoke the script via `pwsh` (PowerShell Core), **not** through the default bash shell. This avoids MSYS / Git-Bash path translation that silently rewrites Unix-style arguments (e.g. `/monorepo/desktop/ui`) into broken Windows paths.

The `git worktree add` step (slow path, triggered when no parked worktree exists) can take several minutes. Use a **300 second timeout**. Do not proceed until it returns a successful exit code.

```
pwsh -ExecutionPolicy Bypass -File C:/Projects/worktree-manager/scripts/Create-Worktree.ps1 -RepoPath "<repoPath>" -RepoName "<repoName>" -BaseBranch "<baseBranch>" -BranchName "<branchName>" -DesktopName "<desktopName>" -WorkItemId <workItemId> -WorkItemTitle "<workItemTitle>" -WorkItemType "<workItemType>" -WorkItemUrl "<workItemUrl>" -RelativeWorkspacePath "<relativeWorkspacePath>" -ProfileName "<profileName>" -SetupCwd "<setupCwd>" -SetupCommand "<setupCommand>" -TerminalCwd "<terminalCwd>" -TerminalCommand "<terminalCommand>" -TerminalProfile "<terminalProfile>"
```

**Parameter notes:**

- Omit `-SetupCwd` and `-SetupCommand` entirely if `$hasSetup` is `false`.
- Omit `-TerminalCwd`, `-TerminalCommand`, and `-TerminalProfile` entirely if `$hasTerminal` is `false`.
- The command above must be passed to the Bash tool as a single line — `pwsh` handles quoting natively, so no backtick line continuations are needed.

---

## Example Usage

```
/create-worktree 88018
```

The prompt will:

1. Ask the user to select a profile (if multiple exist)
2. In parallel: resolve profile config + fetch work item 88018 from Azure DevOps
3. Generate and validate branch name (e.g. `task/88018/implement-feature`)
4. Display a parameter summary
5. Run a single consolidated script that:
   - Fetches the base branch
   - Claims a parked worktree (fast) or creates a new one at `.worktrees/<repo>-N` (slow)
   - Opens the configured workspace in VS Code on a new virtual desktop (`88018-implement-feature`)
   - Opens the Azure DevOps work item in the browser
   - Opens Windows Terminal with two tabs: the first runs the terminal command (e.g. opencode) and the second runs the setup command (e.g. pnpm install) — if configured in the profile
   - Updates `.sessions/sessions.json` and `status.json` to record the worktree is in use

## Error Handling

- Verify work item exists and is accessible before Phase 1 completes
- If branch name uniqueness check fails repeatedly (5+ attempts), report and ask user for a custom branch name
- If `git worktree add` fails, report the error and stop
- If `.sessions/sessions.json` update fails, warn the user but continue
- If `status.json` update fails, warn the user but don't fail the overall operation
