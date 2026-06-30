# FORNAV Claude Code plugins

A self-hosted Claude Code plugin marketplace for FORNAV AL development.

## Plugins

- **fornav-al-reports** — guidance, scaffolding, and review for AL developers integrating with FORNAV reports (temp tables, layouts, report/email/e-invoicing events) in Business Central.
- **fornav-al-tools** — development workflow tools for ForNAV AL extensions (dependency switching between e4 dev and release mode, and project setup).

## Install

```
/plugin marketplace add <git-remote-or-local-path-to-this-repo>
/plugin install fornav-al-reports@fornav-claude-plugins
/plugin install fornav-al-tools@fornav-claude-plugins
```

Once installed, skills auto-trigger when relevant, or invoke directly:
- `/fornav-al-reports:fornav-al-reports` — FORNAV report integration guidance
- `/fornav-al-tools:swap-deps` — swap app.json dependencies between e4 dev and release mode
