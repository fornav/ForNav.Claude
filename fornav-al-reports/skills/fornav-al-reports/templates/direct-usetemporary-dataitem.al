// Pattern: add a temporary DataItem to a FORNAV report you own, populated
// directly in AL (no event subscriber). Use only when you can modify the
// report object itself.
//
// The ReportForNav.OnPreDataItem(...) hook on the temp DataItem is required
// so the FORNAV Designer can introspect and render it — it is easy to forget
// and the layout will silently fail to see the data without it.
//
// Replace <Prefix>, <TempTable>, <ParentDataItem> with real values.
// Source pattern verified against: Developer/TemporaryDataItems.md (ForNav.Documentation repo).

table 50102 "<Prefix> <TempTable>"
{
    DataClassification = ToBeClassified;
    TableType = Temporary;

    fields
    {
        field(1; "Entry No."; Integer) { }
        field(2; "<Value Field>"; Decimal) { }
    }

    keys
    {
        key(Key1; "Entry No.") { Clustered = true; }
    }
}

// Report dataset (relevant extract) — nest under the parent DataItem that
// drives population, not at the top level.
//
// dataitem(<ParentDataItem>; "<ParentTable>")
// {
//     dataitem(Temp<TempTable>; "<Prefix> <TempTable>")
//     {
//         UseTemporary = true;
//         trigger OnPreDataItem()
//         begin
//             ReportForNav.OnPreDataItem('Temp<TempTable>', Temp<TempTable>);
//         end;
//     }
//
//     trigger OnAfterGetRecord()
//     begin
//         GetTempData();
//     end;
// }

local procedure GetTempData()
begin
    Temp<TempTable>.DeleteAll();
    // Populate Temp<TempTable> from <ParentDataItem> here, then Temp<TempTable>.Insert();
end;
