---
name: translate
description: Use when asked to translate an AL Business Central extension, fill in or update .xlf translations, or add a new language to a project's Translations folder — using the ForNAV cmdlet's JSON round-trip so Claude can edit the translations directly instead of a human editing Excel. Covers exporting captions to JSON, filling target-language values, and importing back to .xlf.
---

# Translate an AL project via the ForNAV JSON round-trip

The ForNAV cmdlet module can round-trip translations through **JSON** (not just Excel).
JSON is plain text, so Claude can read the export, fill in the missing target-language
values itself, and import the result back — no human-in-Excel step needed.

Cmdlets used (from `ForNav.Cmdlet.dll`):
- `Invoke-ExportTranslationFromXlfToJson -FromXlf <glob> -ToJson <file>`
- `Invoke-ImportTranslationFromJsonToXlf -FromXlf <g.xlf> -FromJson <file> -ToXlf <folder>`

## ⚠️ Two hard requirements — read first

1. **Run the cmdlets in Windows PowerShell 5.1 (`powershell.exe`), NOT PowerShell 7 (`pwsh`).**
   The DLL targets .NET Framework and calls `AppDomain.get_Evidence()`, which does not
   exist in .NET (Core/5+). Under `pwsh` it fails with
   `Method not found: 'System.Security.Policy.Evidence System.AppDomain.get_Evidence()'`.
   Invoke each cmdlet through `powershell.exe -NoProfile -Command "..."`.
   Pass the module and cmdlet **inline via `-Command`** — do not use
   `-ExecutionPolicy Bypass` (unnecessary, and it's an endpoint-security override).

2. **The project must emit a `.g.xlf`.** That requires `"TranslationFile"` in the
   `features` array of `app.json`. The import uses `<AppName>.g.xlf` as the key source,
   so it must be current (see Step 2).

The module DLL is normally at `C:\Program Files\Reports ForNAV\ForNav.Cmdlet.dll`.
If it's elsewhere, locate it before starting. If it's not installed at all, tell the
user to install the ForNAV cmdlet from https://www.fornav.com/download/ — Claude should
not attempt to download or install it itself.

## Step 1 — Confirm prerequisites

- `app.json` contains `"TranslationFile"` in `features`. If not, tell the user this must
  be added (and the project rebuilt) before translations can be generated; stop.
- Locate `ForNav.Cmdlet.dll`. If it's missing, stop and point the user to
  https://www.fornav.com/download/ to install it. Identify the `Translations/` folder
  (holds `<AppName>.g.xlf` plus one `translation-<locale>.xlf` per language).

## Step 2 — Refresh the generated `.g.xlf`

New or changed captions/tooltips only appear once the project is compiled. Build it so
`Translations/<AppName>.g.xlf` reflects the current source. Either:
- `AL: Package` in VS Code, or
- run the AL compiler directly, e.g.
  `alc.exe /project:"<proj>" /packagecachepath:"<proj>\.alpackages" /out:"<tmp>.app"`
  (the `alc.exe` sits beside `altool.exe` in the AL extension's `bin\win32` folder).

> When running `alc.exe` from a bash/MSYS shell, the `/out:` argument gets mangled by
> path conversion — run it from PowerShell with native Windows paths instead.

## Step 3 — Back up the Translations folder

The import **regenerates** the `translation-*.xlf` files. Copy `Translations/` to a
scratch/backup location first so a bad run is recoverable.

## Step 4 — Export the current translations to JSON

```powershell
powershell.exe -NoProfile -Command 'Import-Module "C:\Program Files\Reports ForNAV\ForNav.Cmdlet.dll"; Invoke-ExportTranslationFromXlfToJson -FromXlf "<proj>\Translations\*.xlf" -ToJson "<scratch>\translations.json"'
```

The `*.xlf` glob pulls the `.g.xlf` (source keys) plus every existing
`translation-<locale>.xlf` (existing targets) into one JSON map.

## Step 5 — Fill the missing target-language values

The JSON is a flat map keyed by the **English source string**, with one entry per
language using **three-letter Windows language IDs** (`ENU`, `NLD`, `DEU`, `FRA`, …):

```json
{
  "Requested Delivery Date": { "ENU": "Requested Delivery Date", "NLD": "Gewenste leverdatum" },
  "Customer update provided": { "ENU": "Customer update provided", "NLD": "" }
}
```

- Entries whose target language (e.g. `NLD`) is **empty or missing** are the untranslated
  ones — usually the newly added captions/tooltips. Fill them in.
- To **add a new language**, add that language key (e.g. `"DEU": "..."`) to every entry.
- Reuse the exact **base-app caption** for standard fields so terminology stays
  consistent (e.g. `Requested Delivery Date` → `Gewenste leverdatum` in nl-NL). For BC
  Dutch use `verkooporder` / `inkooporder` for sales/purchase order.
- Leave a stray `" "` (single-space) key alone — it comes from empty developer notes.
- Do not invent translations for a language you can't produce well; leave those for the
  user and say which entries remain empty.

Edit the JSON file in place (a small script or direct edits). Then verify no intended
entry still has an empty target.

## Step 6 — Import the JSON back to .xlf

```powershell
powershell.exe -NoProfile -Command 'Import-Module "C:\Program Files\Reports ForNAV\ForNav.Cmdlet.dll"; Invoke-ImportTranslationFromJsonToXlf -FromXlf "<proj>\Translations\<AppName>.g.xlf" -FromJson "<scratch>\translations.json" -ToXlf "<proj>\Translations"'
```

`-FromXlf` is the **`.g.xlf`** (keys), `-FromJson` is your edited JSON (values), `-ToXlf`
is the `Translations` folder (regenerated `translation-<locale>.xlf` files land here).

## Step 7 — Verify

- Grep the regenerated `translation-<locale>.xlf` for the new `<target>` values.
- Recompile the project to confirm it still builds clean with the updated translations.
- Report which strings were translated and flag any you want the user to review.
