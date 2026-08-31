# The InvoiceDescriptor object model

`Record "ForNAV InvoiceDescriptor"` and its child tables under `ZugFerd/Autogen/*.Table.al` form an
in-memory object model mirroring the ZUGFeRD/EN16931 CII XML schema: seller/buyer parties, trade line
items, taxes, payment terms/means, trade allowance charges, referenced documents, and more. Each child
collection is exposed through a consistent pair of procedures on the parent record:

```al
InitXxx(var Child: Record "ForNAV Xxx")       // start a new child row (or navigate to the party/etc. slot)
FindFirstXxx(var Child: Record "ForNAV Xxx"): Boolean  // find an existing one, if any
```

For example, on `InvoiceDescriptor` itself:

```al
procedure InitTradeLineItems(var TradeLineItems: Record "ForNAV TradeLineItem")
procedure FindFirstTradeLineItems(var TradeLineItems: Record "ForNAV TradeLineItem"): Boolean
procedure InitTaxes(var Taxes: Record "ForNAV Tax")
procedure FindFirstTaxes(var Taxes: Record "ForNAV Tax"): Boolean
procedure InitTradeAllowanceCharges(var TradeAllowanceCharges: Record "ForNAV TradeAllowanceCharge")
procedure FindFirstTradeAllowanceCharges(var TradeAllowanceCharges: Record "ForNAV TradeAllowanceCharge"): Boolean
```

There are dozens more of these (buyer, seller, ship-to, payment means, referenced documents...) — if you
have access to ZugFerd's source, grep `InvoiceDescriptor.Table.al` and the relevant `Autogen/*.Table.al`
file for the exact name rather than guessing; the naming is consistent but exhaustive, so it's faster to
look it up than to remember it.

## Why you (usually) can't just call `.Insert()` on a child record

These child tables are virtualized over a shared `RecordRef` storage scheme (see
`eDocument.Codeunit.al`). Whether a child record's own `.Insert()`/`.Modify()`/`.Delete()` actually
persists depends on which Business Central version ZugFerd is compiled for:

- **Before BC22**: `InitXxx` populates the child record via a plain `RecordRef.SetTable(Variable)`. A
  record obtained this way is a detached copy — calling its own `.Insert()`/`.Modify()`/`.Delete()`
  compiles fine and appears to "work" in isolation, but silently goes nowhere; the change never reaches
  the document being serialized.
- **BC22 and later**: `RecordRef.SetTable` gained a second `ValidateRelation: Boolean` parameter. Every
  `InitXxx` in ZugFerd passes `true` for it under `#if GE_BC_22_0_0_0` (e.g. `InvoiceDescriptor.InitTaxes`:
  `eDocument.InitRecord(Rec, 47, true).SetTable(Taxes, true)`), which makes the resulting record properly
  bound rather than detached — so on BC22+, calling the child record's own
  `.Insert()`/`.Modify()`/`.Delete()` directly *does* persist correctly.

Because of this split, `"ForNAV eDocument"`'s generic helpers remain the safe, version-agnostic choice —
they work identically regardless of which `#if GE_BC_xx` branch ZugFerd was actually compiled with:

```al
procedure Insert(ChildRec: Variant)
procedure Modify(ChildRec: Variant)
procedure Delete(ChildRec: Variant)
```

**If the app you're writing the subscriber in only ever targets BC22 or later**, you can skip these and
call the child record's own `.Insert()`/`.Modify()`/`.Delete()` directly after populating it via
`InitXxx`/`FindFirstXxx` — simpler, and matches what BC22+ makes possible. If you're not certain of the
minimum BC version, or the app needs to support pre-BC22 environments too, stick with
`eDocument.Insert`/`Modify`/`Delete`, since that path works on every version ZugFerd itself supports.
Either way: get/init the child record via the parent record's own `InitXxx`/`FindFirstXxx` procedure
(e.g. `InvoiceDescriptor.InitNotes`/`FindFirstNotes`, `InitTaxes`/`FindFirstTaxes`) first — never
construct the child record from scratch.

`"ForNAV eDocument"` also has its own generic `FindFirst(ChildRec: Variant): Boolean`, but don't call it
directly — it's an internal implementation detail the generated `FindFirstXxx` wrappers are built on, not
part of the public surface, and (unlike `Insert`/`Modify`/`Delete`) it's `internal`, so it isn't even
visible to a downstream app without an `internalsVisibleTo` grant. *Finding* an existing child record
should always go through the parent record's own `FindFirstXxx` (e.g. `InvoiceDescriptor.FindFirstNotes`)
— it's plain `public`, consistent with every `InitXxx` counterpart, and it's the one that actually filters
to the right child rows for that specific parent instance.

## Worked example: a header note + a custom discount line

This mirrors the pattern in `eSalesInvoice.Codeunit.al`'s invoice-discount handling and
`eServiceCreditNote.Codeunit.al`'s overall structure — adding a trade allowance charge (a
discount/surcharge line, BG-20/BG-21 in EN16931 terms) that the built-in mapping doesn't already add for
this particular scenario, plus a scalar header field.

```al
codeunit 50100 "My Company ZUGFeRD Custom."
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ForNAV eDocument Interface", 'OnAfterDocument2InvoiceDescriptor', '', false, false)]
    local procedure OnAfterDocument2InvoiceDescriptor(var InvoiceDescriptor: Record "ForNAV InvoiceDescriptor")
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        TempTradeAllowanceCharge: Record "ForNAV TradeAllowanceCharge" temporary;
        MapTo: Codeunit "ForNAV Map to eDocument";
        eDocument: Codeunit "ForNAV eDocument";
        EarlyPaymentDiscountPct: Decimal;
    begin
        // .Type only narrows this to "some kind of Invoice" - a Sales Invoice and a Service Invoice both
        // set Type::Invoice identically, so it does NOT tell them apart. Get()'ing the specific table this
        // customization targets is what actually disambiguates: if this fails, it's not a Sales Invoice
        // (could be Service/Purchase, or simply no invoice with this No. in this table), so skip it.
        if InvoiceDescriptor.Type <> InvoiceDescriptor.Type::Invoice then
            exit;
        if not SalesInvoiceHeader.Get(InvoiceDescriptor.InvoiceNo) then
            exit;

        EarlyPaymentDiscountPct := GetCustomEarlyPaymentDiscount(SalesInvoiceHeader);
        if EarlyPaymentDiscountPct = 0 then
            exit;

        // Scalar header field - assign directly, no eDocument.Modify() needed for InvoiceDescriptor's own fields.
        InvoiceDescriptor.PaymentReference := StrSubstNo('%1 (-%2%)', InvoiceDescriptor.PaymentReference, EarlyPaymentDiscountPct);

        // New child row (BG-20 discount): Init, populate, then eDocument.Insert - the version-agnostic
        // choice (see "Why you (usually) can't just call .Insert()" above; TempTradeAllowanceCharge.Insert()
        // would also work here if this app only ever targets BC22+).
        InvoiceDescriptor.InitTradeAllowanceCharges(TempTradeAllowanceCharge);
        MapTo.AddTradeAllowanceCharge(
            TempTradeAllowanceCharge,
            InvoiceDescriptor.Currency,
            InvoiceDescriptor.LineTotalAmount,
            InvoiceDescriptor.LineTotalAmount * EarlyPaymentDiscountPct / 100,
            0,                          // VAT % - 0 here only if the discount itself is genuinely VAT-exempt; check the actual document's VAT rate otherwise
            'Early payment discount',
            1,
            true,                       // IsSummary
            false);                     // ReverseCharge
        eDocument.Insert(TempTradeAllowanceCharge);
    end;

    local procedure GetCustomEarlyPaymentDiscount(SalesInvoiceHeader: Record "Sales Invoice Header"): Decimal
    begin
        // Replace with the customer's actual business rule.
        exit(0);
    end;
}
```

Notes on this example:

- `MapTo.AddTradeAllowanceCharge` and the other helpers on `"ForNAV Map to eDocument"` are `internal` —
  calling them requires the same `internalsVisibleTo` grant as the event subscription itself (see
  `SKILL.md`). If that access isn't available, populate `TempTradeAllowanceCharge`'s fields directly
  instead (check `TradeAllowanceCharge.Table.al` for the field list) and skip the helper.
- `AddTradeAllowanceCharge`'s VAT %/reverse-charge parameters need to match the actual tax treatment of
  the discount, not be hardcoded — the placeholder values above are there to show the call shape, not as
  a value to copy verbatim into a real customization.
- Modifying an *existing* record found via `FindFirstXxx` follows the same shape as inserting a new one,
  just with `eDocument.Modify(...)` instead of `eDocument.Insert(...)` after changing fields — see
  `eSalesInvoice.Codeunit.al`'s `InvoiceDiscountAmountExclVAT` handling for a real example of finding an
  existing `"ForNAV Tax"` row via `InvoiceDescriptor.FindFirstTaxes` and adjusting its amounts.
