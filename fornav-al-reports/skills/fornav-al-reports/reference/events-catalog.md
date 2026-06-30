# FORNAV AL integration events — catalog

Less-frequently-needed integration points beyond the core temp-table pattern covered in `SKILL.md`. All signatures below are verbatim from the FORNAV documentation repo and should still be spot-checked against the installed app source if you're on an unfamiliar version — FORNAV does deprecate events (see the obsolete-events warning in `SKILL.md`).

## Email scenarios

FORNAV Email Templates use Business Central email scenarios to pick a template. The enum is extendable.

Add a custom scenario:

```al
value(50100; "<Prefix> Sales Shipment")
{
    Caption = 'Sales Shipment';
}
```

Map it to a source table — subscribe to `OnBeforeGetSourceTableNo` on `Codeunit::"FORNAV Email Scenario Mapping"`:

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"FORNAV Email Scenario Mapping",
    'OnBeforeGetSourceTableNo', '', false, false)]
local procedure OnBeforeGetSourceTableNo(Source: Enum "Email Scenario";
    var TableNo: Integer; var Handled: Boolean)
begin
    case Source of
        Source::"<Prefix> Sales Shipment":
            TableNo := Database::"Sales Shipment Header";
        else
            exit;
    end;
    Handled := true;
end;
```

Mark it customer-facing (enables FORNAV's per-customer To/Cc/Bcc override logic) — subscribe to `OnBeforeCheckIsCustomer` on the same codeunit:

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"FORNAV Email Scenario Mapping",
    'OnBeforeCheckIsCustomer', '', false, false)]
local procedure OnBeforeCheckIsCustomer(EmailScenario: Enum "Email Scenario";
    var IsCustomer: Boolean; var Handled: Boolean)
begin
    case EmailScenario of
        EmailScenario::"<Prefix> Sales Shipment":
            IsCustomer := true;
        else
            exit;
    end;
    Handled := true;
end;
```

Generate and send an email from AL via `Codeunit "FORNAV Text Builder Interface"`:

```al
procedure EmailFromScenario(RecVar: Variant; EmailScenario: Enum "Email Scenario"; HideMailDialog: Boolean)
var
    TempEmailItem: Record "Email Item" temporary;
    TextBuilderInterface: Codeunit "FORNAV Text Builder Interface";
    TempBlob: Codeunit "Temp Blob";
    RecRef: RecordRef;
    InS: InStream;
    OutS: OutStream;
begin
    RecRef.GetTable(RecVar);
    RecRef.SetRecFilter();

    TextBuilderInterface.GenerateEmail(TempEmailItem, EmailScenario,
        RecRef.Number, RecRef.Field(RecRef.SystemIdNo).Value);

    TempBlob.CreateOutStream(OutS);
    Report.SaveAs(Report::"ForNAV Sales Shipment", '', ReportFormat::Pdf, OutS, RecRef);
    TempBlob.CreateInStream(InS);
    TempEmailItem.AddAttachment(InS, 'AttachmentName.pdf');

    TempEmailItem.Send(HideMailDialog, EmailScenario);
end;
```

Source: `Developer/EmailScenarios.md` in the ForNav.Documentation repo. Further examples: https://github.com/fornav/ForNav.Training/tree/master/FORNAV.EmailScenarios

## E-invoicing (ZUGFeRD / XRechnung)

On `Codeunit::"ForNAV eDocument Interface"`:

| Event | Purpose |
|---|---|
| `OnDocument2InvoiceDescriptor` | Override the ZUGFeRD/XRechnung mapping before FORNAV's standard logic runs. |
| `OnAfterDocument2InvoiceDescriptor` | Customize specific fields after standard mapping has run. |

Source: `Developer/EInvoicing.md`. Expansion of this area is deferred per project notes — verify event signatures directly against the installed app before relying on them for new work.

## Text/HTML splitters

Direct codeunit calls, no event subscription required to use them:

- `Codeunit::"ForNAV HTML Splitter"` — `FillHTML()` splits HTML at `<br>`/`<p>` boundaries. Extension hook: `OnBeforeFillHTML`.
- `Codeunit::"ForNAV Text Splitter"` — `FillText()` splits plain text at line feeds. Extension hook: `OnBeforeFillText`.

Source: `Developer/Splitters.md`.

## Built-in temp-table subscribers

The Report Pack ships its own internal subscribers (registered on the private `OnFillTemporaryTableInternal` event — not accessible from outside the extension) for a number of standard tables, including ledger entry buffers. If the temp table you need already matches one of these, FORNAV populates it automatically and no custom subscriber is needed. See `Report Pack/TemporaryTables.md` → "Built-in Subscribers in the Report Pack" for the current list; it's version-dependent, so check the docs (or the installed app) rather than assuming a table is or isn't covered.
