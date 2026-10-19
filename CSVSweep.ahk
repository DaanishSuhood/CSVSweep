#Requires AutoHotkey v2.0
;@Ahk2Exe-SetMainIcon CSVSweep.ico
;@Ahk2Exe-SetName CSVSweep
;@Ahk2Exe-SetDescription CSVSweep
;@Ahk2Exe-SetVersion 1.0.0

if !A_IsCompiled && FileExist(A_ScriptDir "\CSVSweep.ico")
    TraySetIcon(A_ScriptDir "\CSVSweep.ico")

; ============================================================
; CSVSweep — Search multiple CSV files
; ============================================================

global CsvFiles := []
global Results := []
global MaxCols := 0
global LV := ""
global SB := ""
global FileCountText := ""
global SearchEdit := ""
global FileGroupBox := ""
global SearchGroupBox := ""
global BtnExportList := ""
global BtnClear := ""
global BtnAddToList := ""
global BtnClearList := ""
global BtnToggleView := ""
global ListCountText := ""
global SelectedList := []
global SelectedKeys := Map()
global ViewMode := "results"
global ListFilePath := A_ScriptDir "\CSVSweep_list.dat"
global UndoStack := []
global RedoStack := []

BuildGui()
LoadListFromDisk()
UpdateListCountText()

BuildGui() {
    global LV, SB, FileCountText, SearchEdit
    global FileGroupBox, SearchGroupBox, BtnExportList, BtnClear
    global BtnAddToList, BtnClearList, BtnToggleView, ListCountText

    mainGui := Gui("+Resize +MinSize640x400", "CSVSweep")
    mainGui.SetFont("s10", "Segoe UI")
    mainGui.OnEvent("Size", GuiResize)
    mainGui.OnEvent("Close", GuiClose)

    ; --- File Selection GroupBox ---
    FileGroupBox := mainGui.AddGroupBox("x10 y8 w880 h58", "File Selection")
    mainGui.AddButton("x25 y30 w120", "Browse Files").OnEvent("Click", BrowseFiles)
    mainGui.AddButton("x155 y30 w120", "Scan Folder").OnEvent("Click", ScanFolder)
    FileCountText := mainGui.AddText("x290 y33 w300 h25 0x200", "No files loaded")

    ; --- Search GroupBox ---
    SearchGroupBox := mainGui.AddGroupBox("x10 y75 w880 h58", "Search")
    mainGui.AddText("x25 y99", "Search:")
    SearchEdit := mainGui.AddEdit("x85 y96 w300 vSearchTerm")
    SearchEdit.OnEvent("Change", (*) => "")
    mainGui.AddButton("x395 y96 w80 vBtnSearch Default", "Search").OnEvent("Click", DoSearch)
    mainGui.AddCheckBox("x490 y99 vCaseSensitive", "Case Sensitive")
    mainGui.AddCheckBox("x620 y99 vFuzzySearch", "Fuzzy Search")

    ; Set cue banner placeholder text on search edit
    SendMessage(0x1501, 1, StrPtr("Type a term to search..."), SearchEdit)

    ; --- Results ListView ---
    LV := mainGui.AddListView("x10 y143 w880 h380 +LV0x10000 Grid", ["File"])
    LV.ModifyCol(1, 150)
    LV.OnEvent("DoubleClick", OpenFileFromResult)
    LV.OnEvent("ContextMenu", LVContextMenu)

    ; --- Action Buttons ---
    BtnAddToList := mainGui.AddButton("x10 y533 w120", "Add to List")
    BtnAddToList.OnEvent("Click", AddOrRemoveSelected)
    BtnToggleView := mainGui.AddButton("x140 y533 w100", "View List")
    BtnToggleView.OnEvent("Click", ToggleView)
    BtnExportList := mainGui.AddButton("x250 y533 w120", "Export List")
    BtnExportList.OnEvent("Click", ExportList)
    BtnClearList := mainGui.AddButton("x380 y533 w80", "Clear List")
    BtnClearList.OnEvent("Click", ClearList)
    BtnClear := mainGui.AddButton("x470 y533 w80", "Clear")
    BtnClear.OnEvent("Click", ClearAll)
    ListCountText := mainGui.AddText("x560 y537 w200 h25 0x200", "List: 0 row(s)")

    ; --- Status Bar ---
    SB := mainGui.AddStatusBar(, "Ready")

    ; Ctrl+C copies the current row selection and Ctrl+A selects every row,
    ; but only while the ListView itself has keyboard focus (a native
    ; ListView has no built-in select-all - that's shell/Explorer behavior,
    ; not something the control provides) so this doesn't hijack the search box
    HotIf(IsLVFocused)
    Hotkey("^c", CopySelectedRows)
    Hotkey("^a", SelectAllRows)
    Hotkey("Delete", DeleteSelected)
    Hotkey("^z", Undo)
    Hotkey("^y", Redo)
    HotIf()

    mainGui.Show("w900 h620")
}

GuiResize(thisGui, MinMax, Width, Height) {
    global LV, FileGroupBox, SearchGroupBox, BtnExportList, BtnClear
    global BtnAddToList, BtnClearList, BtnToggleView, ListCountText
    if MinMax = -1
        return

    try {
        margin := 10
        gbWidth := Width - 2 * margin

        ; Resize GroupBoxes to match window width
        FileGroupBox.Move(,, gbWidth)
        SearchGroupBox.Move(,, gbWidth)

        ; Resize ListView to fill available space
        lvY := 143
        lvW := gbWidth
        lvH := Height - lvY - 72
        if lvH < 50
            lvH := 50
        LV.Move(margin, lvY, lvW, lvH)

        ; Reposition action buttons below ListView
        btnY := lvY + lvH + 10
        BtnAddToList.Move(margin, btnY)
        BtnToggleView.Move(margin + 130, btnY)
        BtnExportList.Move(margin + 240, btnY)
        BtnClearList.Move(margin + 370, btnY)
        BtnClear.Move(margin + 460, btnY)
        ListCountText.Move(margin + 550, btnY + 4)
    }
}

GuiClose(thisGui) {
    ExitApp()
}

IsLVFocused(*) {
    global LV
    return DllCall("GetFocus", "ptr") = LV.Hwnd
}

SelectAllRows(*) {
    global LV, SB
    LV.Modify(0, "Select")
    SB.SetText(LV.GetCount() " row(s) selected")
}

; ============================================================
; Open File from ListView Double-Click
; ============================================================

OpenFileFromResult(LV, RowNumber) {
    global CsvFiles
    if RowNumber = 0
        return

    fileName := LV.GetText(RowNumber, 1)
    for filePath in CsvFiles {
        SplitPath(filePath, &name)
        if name = fileName {
            try Run(filePath)
            return
        }
    }
}

; ============================================================
; File Selection
; ============================================================

BrowseFiles(ctrl, *) {
    global CsvFiles, FileCountText

    selected := FileSelect("M",, "Select CSV Files", "CSV Files (*.csv)")
    if !selected || !selected.Length
        return

    ; FileSelect with "M" returns an array: first element is dir, rest are filenames
    dir := selected[1]
    loop selected.Length - 1 {
        filePath := dir "\" selected[A_Index + 1]
        if !HasFile(filePath)
            CsvFiles.Push(filePath)
    }

    FileCountText.Value := CsvFiles.Length " file(s) loaded"
}

ScanFolder(ctrl, *) {
    global CsvFiles, FileCountText

    folder := DirSelect(, 3, "Select folder to scan for CSV files")
    if !folder
        return

    loop Files folder "\*.csv", "R"
        if !HasFile(A_LoopFileFullPath)
            CsvFiles.Push(A_LoopFileFullPath)

    FileCountText.Value := CsvFiles.Length " file(s) loaded"
}

HasFile(path) {
    global CsvFiles
    for f in CsvFiles
        if f = path
            return true
    return false
}

; ============================================================
; Fuzzy Matching
; ============================================================

LevenshteinDistance(s1, s2) {
    len1 := StrLen(s1)
    len2 := StrLen(s2)

    if len1 = 0
        return len2
    if len2 = 0
        return len1

    ; Use two rows instead of full matrix for memory efficiency
    prevRow := []
    currRow := []
    loop len2 + 1
        prevRow.Push(A_Index - 1)
    loop len2 + 1
        currRow.Push(0)

    loop len1 {
        i := A_Index
        currRow[1] := i

        loop len2 {
            j := A_Index
            cost := (SubStr(s1, i, 1) = SubStr(s2, j, 1)) ? 0 : 1

            insert := prevRow[j + 1] + 1
            delete := currRow[j] + 1
            replace := prevRow[j] + cost

            minVal := insert
            if delete < minVal
                minVal := delete
            if replace < minVal
                minVal := replace

            currRow[j + 1] := minVal
        }

        ; Swap rows
        temp := prevRow
        prevRow := currRow
        currRow := temp
    }

    return prevRow[len2 + 1]
}

FuzzyMatch(cellText, searchTerm, caseSensitive := false, threshold := 0.6) {
    if cellText = ""
        return false

    if !caseSensitive {
        cellText := StrLower(cellText)
        searchTerm := StrLower(searchTerm)
    }

    ; Fast path: exact substring match
    if InStr(cellText, searchTerm)
        return true

    ; Check search term against each word in the cell
    words := StrSplit(cellText, [" ", ",", ";", "`t", "/", "\", "-", "_", "."])
    for word in words {
        word := Trim(word)
        if word = ""
            continue

        maxLen := StrLen(word)
        if StrLen(searchTerm) > maxLen
            maxLen := StrLen(searchTerm)

        if maxLen = 0
            continue

        dist := LevenshteinDistance(word, searchTerm)
        similarity := 1 - (dist / maxLen)

        if similarity >= threshold
            return true
    }

    ; Also check against the full cell text for multi-word search terms
    maxLen := StrLen(cellText)
    if StrLen(searchTerm) > maxLen
        maxLen := StrLen(searchTerm)

    if maxLen > 0 {
        dist := LevenshteinDistance(cellText, searchTerm)
        similarity := 1 - (dist / maxLen)
        if similarity >= threshold
            return true
    }

    return false
}

; ============================================================
; CSV Parsing
; ============================================================

ParseCSV(text) {
    rows := []
    row := []
    field := ""
    inQuotes := false
    len := StrLen(text)
    i := 1

    while i <= len {
        ch := SubStr(text, i, 1)

        if inQuotes {
            if ch = '"' {
                if SubStr(text, i + 1, 1) = '"' {
                    field .= '"'
                    i += 2
                } else {
                    inQuotes := false
                    i += 1
                }
            } else {
                field .= ch
                i += 1
            }
            continue
        }

        if ch = '"' {
            inQuotes := true
            i += 1
        } else if ch = "," {
            row.Push(field)
            field := ""
            i += 1
        } else if ch = "`r" {
            i += 1
        } else if ch = "`n" {
            row.Push(field)
            rows.Push(row)
            row := []
            field := ""
            i += 1
        } else {
            field .= ch
            i += 1
        }
    }

    ; Flush trailing field/row if the file didn't end with a newline
    if field != "" || row.Length > 0 {
        row.Push(field)
        rows.Push(row)
    }

    return rows
}

ReadCSVFile(filePath) {
    text := FileRead(filePath, "UTF-8")
    return ParseCSV(text)
}

; ============================================================
; Search Logic
; ============================================================

DoSearch(ctrl, *) {
    global CsvFiles, Results, MaxCols, LV, SB, SearchEdit, ViewMode, BtnToggleView, BtnAddToList

    searchTerm := SearchEdit.Value
    if searchTerm = "" {
        MsgBox("Please enter a term to search.", "CSVSweep", "Icon!")
        return
    }
    if CsvFiles.Length = 0 {
        MsgBox("Please load CSV files first.", "CSVSweep", "Icon!")
        return
    }

    thisGui := ctrl.Gui
    caseSensitive := thisGui["CaseSensitive"].Value
    fuzzyEnabled := thisGui["FuzzySearch"].Value

    ; Reset results
    Results := []
    MaxCols := 0
    seenRows := Map()

    totalFiles := CsvFiles.Length
    skippedFiles := []

    for idx, filePath in CsvFiles {
        fileName := ""
        SplitPath(filePath, &fileName)
        SB.SetText((fuzzyEnabled ? "Fuzzy searching " : "Searching ") idx "/" totalFiles ": " fileName)

        rows := ""
        try {
            rows := ReadCSVFile(filePath)
        } catch as err {
            skippedFiles.Push(fileName ": " err.Message)
            continue
        }

        for rowIdx, row in rows {
            if row.Length > MaxCols
                MaxCols := row.Length

            rowMatched := false
            for cellText in row {
                isMatch := fuzzyEnabled
                    ? FuzzyMatch(cellText, searchTerm, caseSensitive)
                    : InStr(cellText, searchTerm, caseSensitive)
                if isMatch {
                    rowMatched := true
                    break
                }
            }

            if rowMatched {
                key := filePath "|" rowIdx
                if !seenRows.Has(key) {
                    seenRows[key] := true
                    rowData := [fileName]
                    for cellText in row
                        rowData.Push(cellText)
                    Results.Push(rowData)
                }
            }
        }
    }

    ViewMode := "results"
    BtnToggleView.Text := "View List"
    BtnAddToList.Text := "Add to List"
    ShowResults()

    if skippedFiles.Length > 0 {
        msg := "Could not read " skippedFiles.Length " file(s):`n"
        for f in skippedFiles
            msg .= "`n  - " f
        MsgBox(msg, "CSVSweep", "Iconi")
    }
}

; ============================================================
; ListView Population
; ============================================================

MaxDataCols(rows) {
    maxCols := 0
    for row in rows
        if row.Length > maxCols
            maxCols := row.Length
    return maxCols > 0 ? maxCols - 1 : 0
}

PopulateListView(rows, maxCols) {
    global LV

    LV.Opt("-Redraw")
    LV.Delete()

    ; Delete existing columns and rebuild
    while LV.GetCount("Col") > 0
        LV.DeleteCol(1)

    ; Add columns
    LV.InsertCol(1,, "File")
    loop maxCols
        LV.InsertCol(A_Index + 1,, "Col " A_Index)

    ; Add rows
    for row in rows {
        cols := []
        loop maxCols + 1 {
            if A_Index <= row.Length
                cols.Push(row[A_Index])
            else
                cols.Push("")
        }
        LV.Add("", cols*)
    }

    ; Auto-size columns
    LV.ModifyCol(1, 150)
    loop maxCols {
        LV.ModifyCol(A_Index + 1, "AutoHdr")
    }

    LV.Opt("+Redraw")
}

ShowResults() {
    global Results, MaxCols, SB

    PopulateListView(Results, MaxCols)
    SB.SetText(Results.Length " row(s) found")
}

ShowListView() {
    global SelectedList, SB

    PopulateListView(SelectedList, MaxDataCols(SelectedList))
    SB.SetText(SelectedList.Length " row(s) in list")
}

ToggleView(*) {
    global ViewMode, BtnToggleView, BtnAddToList

    if ViewMode = "results" {
        ViewMode := "list"
        BtnToggleView.Text := "View Results"
        BtnAddToList.Text := "Remove Selected"
        ShowListView()
    } else {
        ViewMode := "results"
        BtnToggleView.Text := "View List"
        BtnAddToList.Text := "Add to List"
        ShowResults()
    }
}

; ============================================================
; Export
; ============================================================

CSVEscape(field) {
    if InStr(field, ",") || InStr(field, '"') || InStr(field, "`n") || InStr(field, "`r")
        return '"' StrReplace(field, '"', '""') '"'
    return field
}

JoinCSVRow(fields) {
    line := ""
    for idx, field in fields {
        if idx > 1
            line .= ","
        line .= CSVEscape(field)
    }
    return line
}

ExportList(ctrl, *) {
    global SelectedList, SB

    if SelectedList.Length = 0 {
        MsgBox("No rows in list to export. Select rows and click 'Add to List' first.", "CSVSweep", "Icon!")
        return
    }

    savePath := FileSelect("S16",, "Save List As", "CSV Files (*.csv)")
    if !savePath
        return

    if !InStr(savePath, ".csv")
        savePath .= ".csv"

    SB.SetText("Exporting...")

    try {
        maxCols := MaxDataCols(SelectedList)

        headerCols := ["File"]
        loop maxCols
            headerCols.Push("Col " A_Index)

        text := JoinCSVRow(headerCols) "`r`n"

        for row in SelectedList {
            padded := []
            loop maxCols + 1
                padded.Push(A_Index <= row.Length ? row[A_Index] : "")
            text .= JoinCSVRow(padded) "`r`n"
        }

        if FileExist(savePath)
            FileDelete(savePath)
        FileAppend(text, savePath, "UTF-8")

        SB.SetText("Exported " SelectedList.Length " row(s)")
        MsgBox("List exported to:`n" savePath, "CSVSweep", "Iconi")
    } catch as err {
        MsgBox("Export failed:`n" err.Message, "CSVSweep", "Icon!")
        SB.SetText("Export failed")
    }
}

; ============================================================
; Selected List
; ============================================================

RowKey(cells) {
    key := ""
    for idx, c in cells
        key .= (idx > 1 ? Chr(1) : "") c
    return key
}

GetSelectedRows() {
    global LV

    numCols := LV.GetCount("Col")
    rows := []
    rowNum := 0
    while (rowNum := LV.GetNext(rowNum)) {
        cells := []
        loop numCols
            cells.Push(LV.GetText(rowNum, A_Index))
        rows.Push(cells)
    }
    return rows
}

UpdateListCountText() {
    global SelectedList, ListCountText
    ListCountText.Value := "List: " SelectedList.Length " row(s)"
}

RebuildSelectedKeys() {
    global SelectedList, SelectedKeys
    SelectedKeys := Map()
    for row in SelectedList
        SelectedKeys[RowKey(row)] := true
}

PushUndoSnapshot() {
    global UndoStack, RedoStack, SelectedList
    UndoStack.Push(SelectedList.Clone())
    RedoStack := []
}

SaveListToDisk() {
    global SelectedList, ListFilePath

    text := ""
    for row in SelectedList
        text .= JoinCSVRow(row) "`r`n"

    try {
        if FileExist(ListFilePath)
            FileDelete(ListFilePath)
        if text != ""
            FileAppend(text, ListFilePath, "UTF-8")
    }
}

LoadListFromDisk() {
    global SelectedList, SelectedKeys, ListFilePath

    if !FileExist(ListFilePath)
        return

    try {
        text := FileRead(ListFilePath, "UTF-8")
    } catch {
        return
    }

    for row in ParseCSV(text) {
        if !row.Length
            continue
        key := RowKey(row)
        if !SelectedKeys.Has(key) {
            SelectedKeys[key] := true
            SelectedList.Push(row)
        }
    }
}

AddOrRemoveSelected(*) {
    global ViewMode
    if ViewMode = "list"
        RemoveSelectedFromList()
    else
        AddSelectedToList()
}

DeleteSelected(*) {
    global ViewMode
    if ViewMode = "list"
        RemoveSelectedFromList()
}

AddSelectedToList(*) {
    global SelectedList, SelectedKeys, SB

    selected := GetSelectedRows()
    if !selected.Length {
        SB.SetText("No rows selected")
        return
    }

    newRows := []
    skipped := 0
    for cells in selected {
        if SelectedKeys.Has(RowKey(cells))
            skipped += 1
        else
            newRows.Push(cells)
    }

    if newRows.Length {
        PushUndoSnapshot()
        for cells in newRows {
            SelectedKeys[RowKey(cells)] := true
            SelectedList.Push(cells)
        }
        UpdateListCountText()
        SaveListToDisk()
    }

    SB.SetText(newRows.Length " new row(s) added" (skipped ? " (" skipped " duplicate skipped)" : "") " - " SelectedList.Length " total in list")
}

RemoveSelectedFromList(*) {
    global SelectedList, SelectedKeys, SB

    selected := GetSelectedRows()
    if !selected.Length {
        SB.SetText("No rows selected")
        return
    }

    removeKeys := Map()
    for cells in selected
        removeKeys[RowKey(cells)] := true

    kept := []
    for row in SelectedList
        if !removeKeys.Has(RowKey(row))
            kept.Push(row)

    removedCount := SelectedList.Length - kept.Length
    if !removedCount {
        SB.SetText("No matching row(s) in list")
        return
    }

    PushUndoSnapshot()
    SelectedList := kept
    RebuildSelectedKeys()

    UpdateListCountText()
    SaveListToDisk()
    ShowListView()
    SB.SetText(removedCount " row(s) removed - " SelectedList.Length " total in list")
}

ClearList(*) {
    global SelectedList, SelectedKeys, SB, ViewMode

    if !SelectedList.Length {
        SB.SetText("List already empty")
        return
    }

    PushUndoSnapshot()
    SelectedList := []
    SelectedKeys := Map()
    UpdateListCountText()
    SaveListToDisk()
    if ViewMode = "list"
        ShowListView()
    SB.SetText("List cleared")
}

Undo(*) {
    global UndoStack, RedoStack, SelectedList, SB, ViewMode

    if !UndoStack.Length {
        SB.SetText("Nothing to undo")
        return
    }

    RedoStack.Push(SelectedList.Clone())
    SelectedList := UndoStack.Pop()
    RebuildSelectedKeys()

    UpdateListCountText()
    SaveListToDisk()
    if ViewMode = "list"
        ShowListView()
    SB.SetText("Undo - " SelectedList.Length " row(s) in list")
}

Redo(*) {
    global UndoStack, RedoStack, SelectedList, SB, ViewMode

    if !RedoStack.Length {
        SB.SetText("Nothing to redo")
        return
    }

    UndoStack.Push(SelectedList.Clone())
    SelectedList := RedoStack.Pop()
    RebuildSelectedKeys()

    UpdateListCountText()
    SaveListToDisk()
    if ViewMode = "list"
        ShowListView()
    SB.SetText("Redo - " SelectedList.Length " row(s) in list")
}

; ============================================================
; Clipboard Copy
; ============================================================

TSVEscape(field) {
    if InStr(field, "`t") || InStr(field, '"') || InStr(field, "`n") || InStr(field, "`r")
        return '"' StrReplace(field, '"', '""') '"'
    return field
}

JoinTSVRow(fields) {
    line := ""
    for idx, field in fields {
        if idx > 1
            line .= "`t"
        line .= TSVEscape(field)
    }
    return line
}

JoinRows(lines) {
    text := ""
    for idx, line in lines
        text .= (idx > 1 ? "`r`n" : "") line
    return text
}

CopySelectedRows(*) {
    global SB

    selected := GetSelectedRows()
    if !selected.Length {
        SB.SetText("No rows selected")
        return
    }

    lines := []
    for cells in selected
        lines.Push(JoinTSVRow(cells))

    A_Clipboard := JoinRows(lines)
    SB.SetText(lines.Length " row(s) copied")
}

LVContextMenu(GuiCtrl, Item, IsRightClick, X, Y) {
    global Results, SelectedList, ViewMode

    if (ViewMode = "list" ? !SelectedList.Length : !Results.Length)
        return

    m := Menu()
    m.Add("Copy Selected Row(s)", (*) => CopySelectedRows())
    if ViewMode = "list"
        m.Add("Remove Selected from List", (*) => RemoveSelectedFromList())
    else
        m.Add("Add Selected to List", (*) => AddSelectedToList())
    m.Show()
}

; ============================================================
; Clear
; ============================================================

ClearAll(ctrl, *) {
    global CsvFiles, Results, MaxCols, LV, SB, FileCountText, SearchEdit, ViewMode

    CsvFiles := []
    Results := []
    MaxCols := 0

    ; Leave the grid alone if it's currently showing the list rather than
    ; search results - Clear only resets loaded files / search results.
    if ViewMode = "results" {
        LV.Opt("-Redraw")
        LV.Delete()
        while LV.GetCount("Col") > 0
            LV.DeleteCol(1)
        LV.InsertCol(1, 150, "File")
        LV.Opt("+Redraw")
    }

    FileCountText.Value := "No files loaded"
    SearchEdit.Value := ""
    SB.SetText("Ready")
}
