# Setup — initialise the ForNAV Claude tooling in a Business Central AL project

A checklist to give any BC / AL extension project the same Claude Code setup: the
`fornav-al-tools` plugin (skills: `extract-layout`, `translate`) and the AL MCP server.

Run these steps once per project (steps 1 & 3 are committed to the repo; step 2 is
per-machine).

## Prerequisites (per machine)

- **Claude Code** CLI, authenticated.
- **AL Language extension** (`ms-dynamics-smb.al`) installed in VS Code — provides
  `altool.exe` / `alc.exe`.
- **ForNAV cmdlet module** (`ForNav.Cmdlet.dll`, normally
  `C:\Program Files\Reports ForNAV\`) — needed by the `translate` skill. Install from
  https://www.fornav.com/download/ if missing.
- **Windows PowerShell 5.1** (`powershell.exe`) — the ForNAV cmdlets are .NET Framework
  and do **not** run under PowerShell 7 (`pwsh`).
- **GitHub CLI** (`gh`), authenticated — for issue/PR workflows. `winget install GitHub.cli`
  then `gh auth login`.

## Step 1 — Enable the plugin (committed, team-wide)

Add to the project's `.claude/settings.json` (merge with any existing keys):

```json
{
  "extraKnownMarketplaces": {
    "fornav-claude-plugins": { "source": { "source": "github", "repo": "fornav/ForNav.Claude" } }
  },
  "enabledPlugins": { "fornav-al-tools@fornav-claude-plugins": true }
}
```

On next open, Claude Code registers the marketplace and enables the plugin — the skills
come with it. You'll get a one-time plugin-trust prompt per machine.

> The source is the **published** GitHub marketplace. Changes made only in a local clone
> of `ForNav.Claude` won't be picked up until they're committed and pushed to
> `github.com/fornav/ForNav.Claude`.

## Step 2 — Register the AL MCP server (per machine)

The AL MCP server exposes `al_build` / `al_compile` / `al_publish` / `al_symbolsearch` /
`al_getdiagnostics`, etc. Its command path is machine- and version-specific, so it is
**not** shipped in the plugin. Register it once (user scope covers all your projects):

```bash
# find your installed altool.exe:
#   %USERPROFILE%\.vscode\extensions\ms-dynamics-smb.al-<version>\bin\win32\altool.exe
claude mcp add al --scope user -- "<path-to>\altool.exe" launchmcpserver --transport stdio
```

Prefer `--scope project` (writes `.mcp.json`) only if you want it committed — but note the
absolute path won't be valid on another machine or after the AL extension updates. Approve
the server on first run (`claude` → approve, or `/mcp`).

For cloud publish/symbol-download, run `al_auth_login` once the server is up.

## Step 3 — Ignore personal settings (committed)

Add to the project's `.gitignore` so per-developer overrides never get committed:

```
.claude/settings.local.json
```

## Step 4 — Verify

- `claude mcp list` → the `al` server is listed (approve if pending).
- In a Claude session, `/fornav-al-tools:translate` (and `extract-layout`) are available.

## Optional — project conventions

If the project uses them, mirror these so Claude follows the house style:

- **`_Architecture/`** — technical feature specs (Claude reads these first when building).
- **`_docs/`** — plain-language end-user guides (no AL objects/fields/code).
- A short **CLAUDE.md** note pointing at the `translate` skill for translations, and the
  ID-range / affix conventions for the extension.

## Publishing plugin changes

The plugin lives in `github.com/fornav/ForNav.Claude`. To update the shared tooling: edit
the plugin, bump its `version` in `.claude-plugin/plugin.json` **and** `marketplace.json`,
update `README.md`, commit, and push. Projects pull it via
`/plugin marketplace update fornav-claude-plugins`.
