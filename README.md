# CSVSweep

Searches across many CSV files at once and shows every matching row in one grid. Rows you care about
can be collected into a persistent list and exported as a new CSV.

Script: [`CSVSweep.ahk`](CSVSweep.ahk), also compiled to a standalone `CSVSweep.exe` (available from
[Releases](https://github.com/DaanishSuhood/CSVSweep/releases/latest)).

---

## Requirements

| Requirement | Notes |
| --- | --- |
| [AutoHotkey v2.0+](https://www.autohotkey.com/) | Only needed to run the `.ahk` script; `CSVSweep.exe` runs without it. Declares `#Requires AutoHotkey v2.0` |

No Office, Python, or other dependency — the CSV parser is built into the script.

## Getting started

1. Run `CSVSweep.exe` from the [latest release](https://github.com/DaanishSuhood/CSVSweep/releases/latest)
   (no AutoHotkey install needed), or run `CSVSweep.ahk` with AutoHotkey v2.
2. Load files: **Browse Files** to multi-select CSVs, or **Scan Folder** to pull in every `.csv`
   under a folder **recursively**. Both add to the existing set; duplicates are ignored.
3. Type a term and press **Search** (or `Enter` — the button is the default).
4. Select the rows you want and click **Add to List**.
5. **Export List** writes them out as a CSV.

### Rebuilding the exe

After editing the script, recompile with [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe/releases)
(right-click `CSVSweep.ahk` → *Compile Script*, or from the command line):

```
Ahk2Exe.exe /in CSVSweep.ahk /out CSVSweep.exe /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

The icon (`CSVSweep.ico`) and version info are set by the `;@Ahk2Exe-…` directives at the top of the
script, so keep the `.ico` next to the script when compiling.

## Search options

| Option | Effect |
| --- | --- |
| *(neither ticked)* | Case-insensitive substring match on any cell in the row |
| **Case Sensitive** | Exact-case substring match |
| **Fuzzy Search** | Tolerates typos — see below |

A row is a hit if **any** cell in it matches, and the whole row is shown.

### Fuzzy search

Fuzzy mode first tries a plain substring match (the fast path). Failing that, it computes the
Levenshtein edit distance between the search term and each *word* in the cell — split on spaces,
commas, semicolons, tabs, slashes, backslashes, hyphens, underscores, and dots — and accepts the row
when similarity (`1 - distance / longer length`) reaches **0.6**. The whole cell text is also compared
the same way, so multi-word terms still work.

It is much slower than a substring search, since the distance is computed per word per cell. On a
large set of files, search first without it.

## Working with results

| Action | How |
| --- | --- |
| Select rows | Click, `Ctrl`-click, `Shift`-click |
| Select all | `Ctrl+A` |
| Copy to clipboard | `Ctrl+C` — tab-separated, so it pastes straight into Excel |
| Open the source file | Double-click a row — opens the file the row came from in its default application |
| Right-click | Context menu with copy and add/remove |

`Ctrl+C`, `Ctrl+A`, `Delete`, `Ctrl+Z`, and `Ctrl+Y` are registered with `HotIf(IsLVFocused)`, so they
only fire while the grid itself has keyboard focus and never hijack the search box.

## The list

The list is a working set that survives across searches and across restarts.

| Button | In results view | In list view |
| --- | --- | --- |
| **Add to List** / **Remove Selected** | Adds the selected rows, skipping ones already in the list | Removes the selected rows |
| **View List** / **View Results** | Switches to the list | Switches back to the results |
| **Export List** | Saves the list as a CSV with a `File`, `Col 1`, `Col 2`, … header row | same |
| **Clear List** | Empties the list | same |
| **Clear** | Clears loaded files, results, and the search box — **leaves the list alone** | same |

`Ctrl+Z` / `Ctrl+Y` undo and redo list changes (add, remove, clear). `Delete` removes selected rows
while in list view.

The list is written to **`CSVSweep_list.dat`** next to the script after every change, and reloaded
on startup, so closing the script does not lose it. It is plain CSV despite the extension — the
counter in the corner shows how many rows it holds.

Duplicates are prevented by hashing the full row contents, so the same row found by two different
searches is only stored once.

## How it works

Files are read as **UTF-8** and parsed by a hand-written state machine that handles quoted fields,
escaped `""` quotes inside them, embedded newlines, and a missing trailing newline. Unreadable files
are collected and reported in one dialog at the end rather than stopping the search.

The ListView is rebuilt for each result set: columns are dropped and re-created to match the widest
row found (`File` plus `Col 1…n`), redraw is suspended while rows are added, and data columns are
sized with `AutoHdr`. The window is resizable and the grid grows with it.

## Limitations

- **Comma-delimited only.** Semicolon-separated exports (common on non-English Windows) and
  tab-separated files are not parsed correctly.
- **UTF-8 only.** A CSV saved as ANSI or UTF-16 will read as mojibake or fail.
- **No header handling.** The first row of each file is treated as data, and columns are labelled
  `Col 1`, `Col 2`, … rather than by name — so the same column position in files with different
  layouts lands in the same grid column.
- Everything is parsed on every search; nothing is cached. Large file sets mean a wait each time, and
  the GUI is frozen during it, with progress shown only in the status bar.
- Double-click matches the source file **by filename**, so if two loaded files share a name the wrong
  one may open.
- Export always writes the generic `File` / `Col n` header.
- `CSVSweep_list.dat` lives beside the script (or exe), so it is shared by every copy of the script in that
  folder.
