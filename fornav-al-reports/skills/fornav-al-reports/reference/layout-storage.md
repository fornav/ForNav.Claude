# Where FORNAV layouts actually live

FORNAV layouts are split across **two separate Business Central system tables**, not one. Nothing in the AL object model or the Designer UI makes this obvious, so code that only checks one of them silently misses the other kind of layout. This reference is for anyone writing AL that needs to *enumerate* or *resolve* layouts programmatically — troubleshooting layout activation (which layout wins) is a different topic, covered in `SKILL.md`'s "Layout not picking up your data?" section.

## The two tables

| | `Report Layout List` | `Tenant Report Layout` |
|---|---|---|
| What it holds | **Built-in** layouts — shipped inside an extension via the report object's `rendering` block (`LayoutFile = './Layouts/...docx'`) | **Custom** layouts — uploaded by a customer/partner at runtime, stored in the database |
| Scope | Global (one row per report + layout name + owning app) | Per company via `"Company Name"` (blank = available in every company) |
| Owning-app field | `"Application ID"` — the package ID of the extension that declared the layout. Non-null for real built-in entries. | `"App ID"` / `"Custom Type"` — only meaningful for layouts an extension pushed in programmatically; a genuine customer upload has these blank |
| Populated by | The platform, from the report object's AL declaration, at extension install/compile time | BC's layout upload UI, or an extension writing to the table directly |

Both are standard BC system tables — not FORNAV-specific — but FORNAV's own tooling is what merges them into one coherent picture (see below).

## Reading a layout's DataContract JSON

`Codeunit "ForNAV Layout Interface"` (6188583, `Access = Internal`, in `Core/Layout Interface/LayoutInterface.Codeunit.al`) is what actually opens a layout's `.docx` blob (as a zip), reads `docProps/custom.xml`, and pulls out the `DataContract` custom property (see the `fornav-extract-layout` skill for the same extraction done externally against a raw `.docx` file). It exposes **three overloads** of `ReadDataContract`, and picking the wrong one is the most common mistake:

```al
internal procedure ReadDataContract(ReportId: Integer; LayoutName: Text; AppId: Guid; var DataContract: Text)
internal procedure ReadDataContract(ReportLayoutList: Record "Report Layout List"; var DataContract: Text)
internal procedure ReadDataContract(TenantReportLayout: Record "Tenant Report Layout"; var DataContract: Text)
```

**The `(ReportId, LayoutName, AppId)` overload only searches `Report Layout List`.** It does a `SetRange("Report ID", ReportId); SetRange(Name, LayoutName); SetRange("Application ID", AppId); FindFirst()` and raises an error if nothing matches — it does **not** fall back to `Tenant Report Layout`. If you've resolved a layout name from anywhere that could include a custom/tenant layout (see below), calling this overload will throw for that layout even though the layout genuinely exists.

The safe pattern when you only have a report ID and a layout name (not already knowing which table it's in) is to look it up yourself and pick the matching overload:

```al
ReportLayoutList.SetRange("Report ID", ReportId);
ReportLayoutList.SetRange(Name, LayoutName);
if ReportLayoutList.FindFirst() then
    LayoutInterface.ReadDataContract(ReportLayoutList, DataContract)
else begin
    TenantReportLayout.SetRange("Report ID", ReportId);
    TenantReportLayout.SetRange(Name, LayoutName);
    TenantReportLayout.SetFilter("Company Name", '%1|%2', CompanyName, '');
    if TenantReportLayout.FindFirst() then
        LayoutInterface.ReadDataContract(TenantReportLayout, DataContract);
end;
```

## Enumerating every layout available for a report

Don't hand-roll the merge above for a *list* of layouts — reuse the existing buffer builder. `Codeunit "ForNAV Report Layout Mgt."` → `CreateBuffer(var ReportLayout: Record "ForNAV Report Layout"; CrossCompany: Boolean)` populates a temp buffer table (`table "ForNAV Report Layout"`, 6188483) that already merges both sources into one shape:

```al
var
    TempReportLayout: Record "ForNAV Report Layout" temporary;
    ReportLayoutMgt: Codeunit "ForNAV Report Layout Mgt.";
begin
    TempReportLayout.SetRange("Report ID", ReportId); // optional — omit to get every report's layouts
    ReportLayoutMgt.CreateBuffer(TempReportLayout, false); // CrossCompany = false: current company + global only
```

Under the hood this delegates to `Codeunit "ForNAV Rep Lay Sel RP"` (6188544) — there's an `#if TL` / `#if not TL` swapped pair of implementations (`TLReportLayoutSelectionRP.Codeunit.al` vs `ReportLayoutSelectionRP.Codeunit.al`); in practice `TL` is on for essentially every real build, so the `TL` variant is the one that runs. It:

1. Queries `Report Layout List` filtered to non-null `"Application ID"` (excludes junk/placeholder rows), plus any `"Report ID"` filter already set on the record you passed in.
2. Queries `Tenant Report Layout` filtered by the same `"Report ID"` filter, and by `"Company Name" in [CompanyName, '']` unless `CrossCompany = true`.
3. Filters **both** queries down to FORNAV reports only, via `Codeunit "ForNAV Check Is ForNAV Report".IsForNAVReport(...)` — non-FORNAV reports never show up in the buffer even if they happen to have layouts in these tables.
4. Inserts one buffer row per layout found, with `"Built-in"` set to true for `Report Layout List` rows (and for `Tenant Report Layout` rows whose `"Custom Type"`/`"App ID"` matches the running extension), `"Layout Name"`, `Description`, `"Company Name"`, `"Layout App ID"`, and — on BC27+/28+ — `"Is Obsolete"` / `"Layout Status"`.

If you pre-set a filter on `"Report ID"` before calling `CreateBuffer` (as shown above), it's honored by both underlying queries — so the same call works for "one report" and "every report" callers, and (via `Rec.GetFilter("Report ID")`) transparently supports OData-style filter expressions if you're populating an API page's temp source table from a `$filter`.

## Where this is used today

- `Core/HealthCheck/HealthCheckReport.Codeunit.al` — health check's layout/dataset-match validation. Built-in only (`Report Layout List` directly).
- `Report Pack/Layout Module/TranslateReport.Report.al`'s `GetAvailableLayouts()` / `GenerateTranslationsForReport()` — the translation wizard's layout picker, built on `CreateBuffer`.
- `Report Pack/MCP/ReportAPI.Page.al`'s `getLayoutDataContract` bound action (`Core/Report.Table.al`'s `ComposeLayoutDataContract`) — tries `Report Layout List` first, falls back to `Tenant Report Layout`, so it resolves either kind of layout by name.
- `Report Pack/MCP/ReportLayoutAPI.Page.al` — read-only discovery API listing every layout (built-in + custom) for a report or set of reports, built on `CreateBuffer`. Exists specifically so an external caller can find a valid `layoutName` to pass into `getLayoutDataContract`.

## Gotchas

- **The 3-arg `ReadDataContract` overload silently can't see custom layouts.** This is the single most likely bug: someone lists layouts via `CreateBuffer` (which correctly includes both kinds), then feeds a layout name into the 3-arg `ReadDataContract` overload and it throws for any tenant/custom entry.
- **`"Application ID"` on `Report Layout List` is not always the report's own owning app.** A different extension can register a built-in layout for a report it doesn't own. Don't assume you can CalcFields your way to the right AppId from the report object alone — look up the actual `Report Layout List` row and use *its* `"Application ID"`.
- **`Tenant Report Layout` rows can be company-scoped or global.** Always filter `"Company Name" in [CompanyName, '']` (or the equivalent `SetFilter('%1|%2', ...)`) rather than an exact match — a blank company name means "every company," not "no company."
