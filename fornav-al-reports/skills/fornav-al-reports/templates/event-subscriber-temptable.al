// Pattern: populate a temporary DataItem/Record in a FORNAV report layout
// without modifying the report AL. Requires the DataItem/Record to be marked
// Temporary (+ AutoPopulate for DataItems) in the FORNAV Designer.
//
// Replace <Prefix>, <TableName>, <ParentTable> and field lists with real values.
// Source pattern verified against: Report Pack/TemporaryTables.md (ForNav.Documentation repo)
// and Core/TempTable.Codeunit.al (ForNav.ReportPack source).

table 50100 "<Prefix> <TableName>"
{
    DataClassification = SystemMetadata;
    TableType = Temporary;

    fields
    {
        field(1; "<Key Field>"; Code[20]) { DataClassification = SystemMetadata; }
        field(2; "<Value Field>"; Decimal) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(Key1; "<Key Field>") { Clustered = true; }
    }

    // Keep the fill logic here so the subscriber below stays thin.
    procedure GetFrom<ParentTable>(Parent: Record "<ParentTable>")
    begin
        // Populate this temp table from Parent.
    end;
}

codeunit 50101 "<Prefix> Fill <TableName>"
{
    [EventSubscriber(ObjectType::CodeUnit, Codeunit::"ForNAV TempTable",
        'OnFillTemporaryTable', '', false, false)]
    local procedure FillTempTableOn<TableName>(ReportID: Integer; ChildDataItemId: Text;
        ParentRecRef: RecordRef; var TempRecRef: RecordRef; var IsHandled: Boolean)
    var
        Temp<TableName>: Record "<Prefix> <TableName>" temporary;
        Parent: Record "<ParentTable>";
    begin
        if IsHandled
            or (TempRecRef.Number <> Database::"<Prefix> <TableName>")
            or (ParentRecRef.Number <> Database::"<ParentTable>")
        then
            exit;

        ParentRecRef.SetTable(Parent);
        TempRecRef.SetTable(Temp<TableName>);

        Temp<TableName>.GetFrom<ParentTable>(Parent);

        TempRecRef.Copy(Temp<TableName>, true);
        IsHandled := true;
    end;
}
