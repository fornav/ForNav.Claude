# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A self-hosted Claude Code plugin marketplace for FORNAV AL development. It defines two installable plugins that add skills to Claude Code sessions used for Business Central / AL extension work.

## Installing into a Claude Code session

```
/plugin marketplace add https://github.com/fornav/ForNav.Claude
/plugin install fornav-al-reports@fornav-claude-plugins
/plugin install fornav-al-tools@fornav-claude-plugins
```

Once installed, skills auto-trigger on relevant context, or can be invoked directly:
- `/fornav-al-reports:fornav-al-reports` — FORNAV report integration guidance and scaffolding
- `/fornav-al-tools:swap-deps` — swap `app.json` dependencies between e4 dev and release mode

## Repository structure

```
.claude-plugin/marketplace.json          # Marketplace definition — lists plugins and their source dirs
fornav-al-reports/
  .claude-plugin/plugin.json             # Plugin manifest (name, version, author)
  skills/fornav-al-reports/
    SKILL.md                             # Skill definition (frontmatter triggers + full guidance)
    reference/events-catalog.md          # Less-common integration events (email, e-invoicing, splitters)
    templates/
      event-subscriber-temptable.al      # Copy-ready AL for the OnFillTemporaryTable pattern
      direct-usetemporary-dataitem.al    # Copy-ready AL for the UseTemporary DataItem pattern
fornav-al-tools/
  .claude-plugin/plugin.json             # Plugin manifest
  skills/swap-deps/
    SKILL.md                             # Skill definition — reads/writes app.json in the target repo
```

## Plugin / skill anatomy

- **`marketplace.json`** — root index; each entry has `name`, `source` (relative dir), `description`, `version`.
- **`plugin.json`** — per-plugin identity; fields: `name`, `version`, `description`, `author`.
- **`SKILL.md`** — the main artifact; YAML frontmatter (`name`, `description`) controls when the skill auto-triggers. The body is the instruction set Claude reads when the skill activates.
- **`templates/`** and **`reference/`** — supporting files that SKILL.md references by relative path; they're loaded on demand, not automatically.

## Domain context

**FORNAV** is a report-layout-designer product for Business Central. These plugins target AL developers writing *extensions that consume or extend* FORNAV — not FORNAV's own product source (`ForNav.ReportPack`).

Key concepts carried in the skills:
- The primary integration point is `Codeunit::"ForNAV TempTable"` → event `OnFillTemporaryTable` (public `[IntegrationEvent]`). The older `OnForNAVFillTemporaryTableForNAV` is `[Obsolete]` since FORNAV 8.2; the third event `OnFillTemporaryTableInternal` is `[InternalEvent]` and not subscribable from outside the extension.
- FORNAV's reserved app ID range: **6188471–6189470** and publisher prefix `ForNAV` — never use these in customer/partner extensions.
- `swap-deps` switches `app.json` between a single e4-dev dependency (`d6978c22-...`) and the normal three-package release set (Language Module, Core, Customizable Report Pack), all at version `8.2.0.0`.

## Adding or modifying skills

1. To add a new skill to an existing plugin, create a subdirectory under `skills/` (e.g. `fornav-al-tools/skills/new-skill/`) with a `SKILL.md`. The frontmatter `description` field is what Claude uses to decide when to auto-trigger the skill — write it as a precise trigger condition, not a general description.
2. To add a new plugin, create its directory with `.claude-plugin/plugin.json` and a `skills/` tree, then register it in `.claude-plugin/marketplace.json`.
3. Templates and reference files are plain text/AL/Markdown — reference them from `SKILL.md` with relative paths. They are not auto-loaded; `SKILL.md` must explicitly instruct Claude to read them when needed.

## Keeping README.md in sync

After any change that adds, removes, or renames a plugin, skill, template, or reference file — **always update `README.md`** to reflect the change. Specifically:

- If a skill is added or removed: update the plugins table, the skills reference section (name, auto-trigger condition, manual invocation command, and what it covers), and the repository layout tree.
- If a skill's trigger condition or behaviour changes materially: update its entry in the skills reference section.
- If a plugin is added or removed: update the plugins table, add/remove its skills reference section, update the install commands, and update the repository layout tree.
- If a template or reference file is added or removed: update the repository layout tree and any skill description that references it.
