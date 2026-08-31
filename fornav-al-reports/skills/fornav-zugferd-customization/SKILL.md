---
name: fornav-zugferd-customization
description: Customize or extend ZUGFeRD/XRechnung/Factur-X e-invoice XML output in the ForNAV E-invoicing (ZugFerd) Business Central AL extension by subscribing to the "ForNAV eDocument Interface" codeunit's OnAfterDocument2InvoiceDescriptor event. Use this whenever the user wants to add, correct, or override a field/line/note/reference in the generated ZUGFeRD/EN16931 invoice XML, mentions the InvoiceDescriptor record, asks about BT-xxx business terms, XRechnung profiles, Factur-X, or wants a customer-specific tweak to the e-invoice mapping — even if they don't name the event directly. Also use it when the user asks why a ZUGFeRD customization for another app/extension won't compile against ZugFerd.
---

# ZUGFeRD customization via OnAfterDocument2InvoiceDescriptor

## Start here: the internal-access gotcha

`OnAfterDocument2InvoiceDescriptor` is declared `internal` in ZugFerd's `eDocumentInterface.Codeunit.al`:

```al
[IntegrationEvent(false, false)]
internal procedure OnAfterDocument2InvoiceDescriptor(var InvoiceDescriptor: Record "ForNAV InvoiceDescriptor")
begin
end;
```

An `internal` procedure in AL can only be subscribed to from the same app, or from an app whose ID is
listed under `internalsVisibleTo` in ZugFerd's `app.json`. Before writing a single line of subscriber
code, ask whoever maintains ZugFerd to confirm the customer/partner app is listed there. If it isn't, the
subscriber will fail to compile with an access error no matter how correct the AL is — and the fix isn't
in the subscriber, it's adding that app's id/name/publisher to ZugFerd's `internalsVisibleTo` array (a
ZugFerd-side change you can't make from a downstream extension, so flag this rather than silently
attempting workarounds like copying the event elsewhere).

If the customization lives inside ZugFerd itself (e.g. you're extending ForNAV's own codebase, not a
downstream customer app), this doesn't apply — skip straight to writing the subscriber.

A downstream app also needs an ordinary AL `dependencies` entry on `"ForNAV E-invoicing"` (id
`9347ed4c-a512-4ff0-a15e-6344804918f9`) in its own `app.json` to resolve the symbols at all —
`internalsVisibleTo` only grants *access*, it doesn't substitute for the dependency declaration.

This is a single, unified gate, not a per-procedure one: `internalsVisibleTo` access is granted at the
app level, so once a customer/partner app is listed, it can both subscribe to the event *and* call the
other `internal` helper codeunits used while building up `InvoiceDescriptor` (e.g. `"ForNAV Map to
eDocument"`, whose `AddTradeAllowanceCharge`/`AddParty`/etc. are all `internal` too — see
[`reference/object-model.md`](reference/object-model.md)). `"ForNAV eDocument"`'s `Insert`/`Modify`/
`Delete` for child records are `Access = Public` and callable from any app either way — its own
`FindFirst` overloads are `internal`, but that's moot: don't call those directly at all, use the
generated `FindFirstXxx` procedure on the parent record instead (see below), which is always public.

## Which event to use

There are two related events, fired at different points in `eDocument.Codeunit.al`'s `ToJson`:

- **`OnDocument2InvoiceDescriptor`** fires *before* the built-in mapping codeunit runs. Setting
  `InvoiceDescriptor.Type` to anything other than `Unknown` here skips the built-in mapping entirely —
  this is a full replacement, not a customization, and should only be reached for if the user explicitly
  wants to replace the mapping for a whole document type.
- **`OnAfterDocument2InvoiceDescriptor`** fires *after* the mapping codeunit (`eSalesInvoice`,
  `eSalesCreditNote`, `eServiceInvoice`, `eServiceCreditNote`, `ePurchaseInvoice`,
  `ePurchaseCreditNote`, or their `...BC` legacy counterparts) has fully populated `InvoiceDescriptor`
  from the posted document, and *before* it's serialized to JSON/XML. This is the right event for
  essentially every real customization request: the built-in mapping already handles the bulk of
  EN16931/ZUGFeRD compliance (tax categories, reverse charge detection, currency, payment terms), so
  default to patching or adding specific fields here rather than reaching for the replacement event.

## Writing the subscriber

```al
codeunit 50100 "My Company ZUGFeRD Custom."
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ForNAV eDocument Interface", 'OnAfterDocument2InvoiceDescriptor', '', false, false)]
    local procedure OnAfterDocument2InvoiceDescriptor(var InvoiceDescriptor: Record "ForNAV InvoiceDescriptor")
    begin
        // InvoiceDescriptor.InvoiceNo, .Type (Invoice/CreditNote), .Currency, etc. are already set.
        // Scalar field on the header (BT-83, "a textual value used to establish a link between the
        // payment and the invoice"): assign directly, no explicit Modify() needed for a temporary record.
        InvoiceDescriptor.PaymentReference := MyCustomPaymentReferenceFormat(InvoiceDescriptor);
    end;
}
```

`.Type` is `Enum "ForNav InvoiceType"` — the full BT-3/UNTDID 1001 document type code, with around 40
values (`DebitNote`, `Correction`, `PrepaymentInvoice`, `SelfBilledInvoice`, `Cancellation`, ...), not
just a plain Invoice/CreditNote flag. Today the built-in mapping codeunits only ever set it to `Invoice`
or `CreditNote` for standard posted-document flows, so checking `.Type = InvoiceDescriptor.Type::Invoice`
is safe in practice — but that's a fact about the current mapping code, not a guarantee baked into the
enum itself, so don't assume it stays that way without checking.

**`.Type` and `.Name` don't tell *sibling* document types apart.** A Sales Credit Memo and a Service
Credit Memo both get `Type := CreditNote` and `Name := 'GUTSCHRIFT'` identically (compare
`eSalesCreditNote.Codeunit.al` against `eServiceCreditNote.Codeunit.al`) — same for the Invoice pair. If
the customization is specific to one of Sales/Service/Purchase, `.Type` alone won't distinguish them; you
have to `Get()` the actual originating document via `.InvoiceNo` (e.g. `Service Cr.Memo Header.Get(...)`)
and let that lookup succeed or fail to know which one you're looking at. There's no "source table" field
on `InvoiceDescriptor` itself for this — the `Get()` call *is* the disambiguation mechanism, not a
convenience shortcut.

For anything beyond a couple of scalar field tweaks, read
[`reference/object-model.md`](reference/object-model.md) next — it covers:

- How the `Autogen/*.Table.al` child collections (trade line items, parties, taxes, trade allowance
  charges, payment means, referenced documents...) work, and when a child record's own
  `.Insert()`/`.Modify()`/`.Delete()` persists correctly versus when it silently doesn't — it depends on
  whether ZugFerd is compiled targeting BC22+ (a `RecordRef.SetTable` flag introduced in BC22 changes
  this), so `"ForNAV eDocument"`'s `Insert`/`Modify`/`Delete` helpers are the safe, version-agnostic
  default unless you know the app you're writing only ever targets BC22 or later.
- A full worked example: adding a header note and a custom trade allowance charge line, closely
  following the patterns already used in `eSalesInvoice.Codeunit.al` and
  `eServiceCreditNote.Codeunit.al`.

## Profile awareness

Some business terms are only valid, or only mandatory, in specific ZUGFeRD profiles (Basic, Comfort,
Extended, XRechnung, ...) — if the user's customization is profile-specific, don't apply it
unconditionally to every profile. `InvoiceDescriptor` does have a `Profile` field
(`Autogen/Profile.Enum.al`, enum `"ForNav Profile"` — a different, ZUGFeRD-specific enum from
`"ForNav Setup"."ForNAV Profile"`/`"ForNav Zugferd Profile"`, which is the company-wide configuration
setting), but as of this writing none of the mapping codeunits actually populate it before
`OnAfterDocument2InvoiceDescriptor` fires — if you have access to ZugFerd's source, check with
`grep -rn 'InvoiceDescriptor.Profile' ZugFerd/` before relying on it, since this could change; if you
don't have source access, ask whoever maintains ZugFerd to confirm. If it's still unset, the only way to
know the active profile is to read `"ForNAV Setup"."ForNAV Profile"` directly (and note `"ForNAV
Setup"."ForNAV Enable ZF per Customer"`/`Customer."ForNAV Add ZUGFeRD"` control *whether* ZUGFeRD is
generated per customer at all, not which profile) — be aware this reads the *configured* profile, not
necessarily proof of exactly what this specific document was mapped against, since the two could in
principle diverge (e.g. a setup change between posting and printing).

## When to check the actual standard

The ZUGFeRD/Factur-X/EN16931 standard evolves — FeRD (Forum elektronische Rechnung Deutschland) publishes
new versions with new profiles and new BR-DE (German XRechnung) business rules periodically. Training
data about specific BT-xxx business term semantics, cardinality, or validation rules can be stale. Before
telling a user a field is mandatory/optional/invalid for a given profile, or implementing a rule that
depends on exact standard semantics, fetch the current specification rather than relying on memory:

> https://www.ferd-net.de/en/download-zugferd

This is FeRD's own download page and always points at the current ZUGFeRD version's documentation and
schema — follow its links to the specific version in question when precision matters.

## Testing

1. Compile the customer/partner app against ZugFerd's `.alpackages` (or the freshly built ZugFerd `.app`
   if ZugFerd itself changed) to confirm the subscriber resolves — this is where an `internalsVisibleTo`
   problem shows up first.
2. Exercise the actual print/attach path rather than trusting the compile alone. ZugFerd's own test
   project (`ZugFerd Test/ZugFerd.Codeunit.al`, if you have access to it) has the established pattern for
   this: `Report.SaveAs(...)` against a posted document, which runs the full mapping + event chain
   end-to-end. Mirror that pattern for the document type being customized (Sales/Service Invoice/Credit
   Memo) rather than only checking `InvoiceDescriptor` state in isolation, since the real bug surface is
   usually in how the value ends up (or doesn't) in the final XML.
3. There's no live Business Central test environment available in most dev sandboxes — if one isn't
   reachable, say so explicitly rather than claiming the print path was verified when only compilation
   was checked.
