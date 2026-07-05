---
name: fornav-extract-layout
description: Use when asked to extract, inspect, or view the DataContract or layout JSON from a FORNAV report .docx layout file, or from an AL report file that references a FORNAV .docx layout. Also use when troubleshooting FORNAV report dataset or field availability by examining what the layout's DataContract declares.
---

# Extract FORNAV layout contract and design JSON

Extracts the `DataContract` (dataset description) and `Json` (visual layout design) from a FORNAV `.docx` layout file. The `.docx` is a zip archive; both values are plain JSON strings stored in `docProps/custom.xml` as `<vt:lpwstr>` elements.

## Step 1 — Resolve the .docx path

**If given a `.docx` file directly:** use that path as-is.

**If given an `.al` file:** grep it for the layout file declaration. Two forms exist:

```al
WordLayout = './Layouts/SomeReport.docx';    // older Word-style declaration
LayoutFile = './Layouts/SomeReport.docx';    // Custom rendering block (preferred)
```

Resolve the found path relative to the `.al` file's directory. If both forms appear (the `#if CUSTOM` pattern in FORNAV's own pack), use `LayoutFile` — that's the active FORNAV path.

## Step 2 — Extract docProps/custom.xml

The `.docx` is a standard zip archive. Use PowerShell's `System.IO.Compression.ZipFile`:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($docxPath)
$entry = $zip.Entries | Where-Object { $_.FullName -eq 'docProps/custom.xml' }
$reader = New-Object System.IO.StreamReader($entry.Open())
$xmlContent = $reader.ReadToEnd()
$reader.Close()
$zip.Dispose()
```

## Step 3 — Parse the XML and extract properties

Confirmed structure from `ForNAV VAT Sales Invoice.docx`:

```xml
<op:Properties xmlns:op="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties">
  <op:property name="Document">
    <vt:lpwstr xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">base64...</vt:lpwstr>
  </op:property>
  <op:property name="DataContract">
    <vt:lpwstr xmlns:vt="...">{ "DataContract": { "Version": 1, "DataItems": { ... } } }</vt:lpwstr>
  </op:property>
  <op:property name="Json">
    <vt:lpwstr xmlns:vt="...">{ "@ReportsForNavVersion": "...", "Bands": { ... } }</vt:lpwstr>
  </op:property>
</op:Properties>
```

- `Document` — base64-encoded binary blob consumed by the rendering engine. Not human-readable; skip it.
- `DataContract` — plain JSON describing the dataset: data items, field numbers, captions, lookups.
- `Json` — plain JSON with the FORNAV Designer's visual layout (bands, controls, source expressions).

Parse with PowerShell (the `lpwstr` child is found via PS's namespace-stripping XML dynamic properties):

```powershell
[xml]$xml = $xmlContent
$props = @{}
$xml.Properties.property | ForEach-Object {
    $props[$_.name] = $_.lpwstr.InnerText
}
$dataContract = $props['DataContract']
$layoutJson   = $props['Json']
```

## Step 4 — Write output files

Write each property next to the `.docx`, replacing `.docx` with `.DataContract.json` and `.Layout.json`:

```powershell
$base = [System.IO.Path]::ChangeExtension($docxPath, $null).TrimEnd('.')
Set-Content -Path "$base.DataContract.json" -Value $dataContract -Encoding utf8
Set-Content -Path "$base.Layout.json"       -Value $layoutJson   -Encoding utf8
```

Report both output paths to the user.

## Step 5 — Summarize key DataContract contents

After writing, parse the `DataContract` JSON and report:

- Top-level data items (keys under `DataContract.DataItems`)
- For each data item: the field names (keys under `Fields`)

```powershell
$dc = $dataContract | ConvertFrom-Json
$dc.DataContract.DataItems.PSObject.Properties | ForEach-Object {
    $item = $_.Name
    $fields = $_.Value.Fields.PSObject.Properties.Name -join ', '
    Write-Output "$item : $fields"
}
```

This gives the user an immediate overview of what the layout knows about, without having to open the file manually.
