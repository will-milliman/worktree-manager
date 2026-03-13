---
argument-hint: "<worktree-id>"
---

# Open Worktree (Resume a Suspended Worktree)

Resume a worktree that was previously suspended with `/close-worktree`. This recreates the virtual desktop, reopens the VS Code workspace, and opens the Azure DevOps work item and GitHub pull request (if one exists) in the browser. The git worktree is already intact — no git operations are needed.

The flow has two phases:

1. **Gather all information** (resolve session, profile, and construct parameters)
2. **Run a single consolidated PowerShell script** (all mechanical work happens here)

Do not run any terminal commands until Phase 2.

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
4. Derive the worktree ID from the selected session's `worktreePath` (last path segment, e.g. `rainier-3`) and proceed to Phase 1.

---

## Phase 1 — Gather Information

Resolve the session key and all script parameters from config files. Do not run any terminal commands in this phase.

1. **Resolve session key from `status.json`**

   Read `C:/Projects/worktree-manager/status.json` and look up the branch for the worktree ID. Extract the task number from the branch name (e.g., `task/90149/update-header` → session key `90149`).

   If the branch doesn't match `task/<number>/...`, report the error and stop.

2. **Load session entry from `sessions.json`**

   Read `C:/Projects/worktree-manager/.sessions/sessions.json` and look up the entry for the resolved session key.

   If no entry exists, report the error and list available sessions as a hint. Then stop.

   Extract from the session entry:

   | Variable        | Source                          |
   | --------------- | ------------------------------- |
   | `$worktreePath` | `worktreePath` field            |
   | `$branchName`   | `branch` field                  |
   | `$desktopName`  | `desktopName` field             |
   | `$profileName`  | `profile` field                 |
   | `$workItemUrl`  | `workItemUrl` field (may be missing) |

   If `$workItemUrl` is missing or empty, construct the fallback:

   ```
   https://dev.azure.com/mgalfadev/5d438345-7020-4631-a370-020f9319088b/_workitems/edit/<session-key>
   ```

3. **Resolve workspace path and terminal config from profile**

   Read `config/profiles.json` and find the profile matching `$profileName`. Extract the `workspace` field and construct the full path:

   ```
   <worktreePath><workspace-path-from-profile>
   ```

   For example: `C:/Projects/worktree-manager/.worktrees/rainier-2/monorepo/desktop/ui/.vscode/integrate.code-workspace`

   Also check if the profile has a `terminal` object. If so, extract:

   | Variable            | Source                                                          |
   | ------------------- | --------------------------------------------------------------- |
   | `$hasTerminal`      | `true` if profile has a `terminal` object, otherwise `false`    |
   | `$terminalDir`      | `<worktreePath><terminal.cwd>` (full path to terminal directory)|
   | `$terminalCommand`  | `terminal.command` (e.g. `opencode`)                            |
   | `$terminalProfile`  | `terminal.profile` if present (e.g. `Worktree`)                |

   Also check if the profile has a `setup` object. If so, extract:

   | Variable            | Source                                                          |
   | ------------------- | --------------------------------------------------------------- |
   | `$hasSetup`         | `true` if profile has a `setup` object, otherwise `false`       |
   | `$setupDir`         | `<worktreePath><setup.cwd>` (full path to setup directory)      |
   | `$setupCommand`     | `setup.command` (e.g. `pnpm install && pnpm run dev:setup`)     |

---

## Phase 2 — Run Consolidated Script

Call `scripts/Open-Worktree.ps1` as a **single terminal execution**, passing all values resolved in Phase 1 as named parameters.

**Important:** Always invoke the script via `pwsh` (PowerShell Core), **not** through the default shell. This avoids variable expansion and redirection issues from nested PowerShell sessions.

```
pwsh -ExecutionPolicy Bypass -File C:/Projects/worktree-manager/scripts/Open-Worktree.ps1 -WorktreePath "<worktreePath>" -BranchName "<branchName>" -DesktopName "<desktopName>" -SessionKey "<sessionKey>" -WorkItemUrl "<workItemUrl>" -WorkspacePath "<workspacePath>" -TerminalDir "<terminalDir>" -TerminalCommand "<terminalCommand>" -TerminalProfile "<terminalProfile>" -SetupDir "<setupDir>" -SetupCommand "<setupCommand>"
```

The command above must be passed to the Bash tool as a single line.

**Parameter notes:**

- Omit `-TerminalDir`, `-TerminalCommand`, and `-TerminalProfile` entirely if `$hasTerminal` is `false`.
- Omit `-SetupDir` and `-SetupCommand` entirely if `$hasSetup` is `false`.

---

## Example Usage

```
/open-worktree rainier-1
/open-worktree
```

Either form will:

1. Load the saved session metadata from `sessions.json`
2. Call `Open-Worktree.ps1` which:
   - Creates (or reuses) the virtual desktop with the original name and switches to it
   - Opens the VS Code workspace
   - Opens Windows Terminal with two tabs: the first runs the terminal command (e.g. opencode) and the second runs the setup command (e.g. pnpm install) — if configured in the profile
   - Opens the Azure DevOps work item in the browser
   - Opens the GitHub pull request in the browser (if one exists)
   - Removes the session entry from `sessions.json`

## Error Handling

- If no entry exists for the worktree ID in `sessions.json`, report the error and list available sessions (if any)
- If `New-WorktreeDesktop` or `Switch-WorktreeDesktop` fails, the script reports the error and stops
- If VS Code fails to launch, the script reports the error but continues with browser steps
- If `$session.workItemUrl` is missing, construct the fallback URL before calling the script
- If `gh` CLI is not installed or no PR exists, the script skips the PR step silently
- If `sessions.json` cannot be updated, the script warns but doesn't fail
