# minute

minute is a compact, native macOS slip-box for small, linked Markdown notes.
It combines a keyboard-first note index with a direct rich-text editor: Markdown
shortcuts become formatting in place, without separate edit and preview modes.

## Features

- One portable UTF-8 Markdown file per note
- Timestamp filenames such as `202609130747 Progressive disclosure.md`
- WYSIWYG-style headings, emphasis, inline code, quotes, and lists
- Bullet, numbered, nested, and task-list editing behavior
- `@` completion using full note filenames
- Clickable note links and backlinks
- Search and complete keyboard navigation
- Recoverable deletion through macOS Trash with in-app Undo
- Bundled JetBrains Mono with Ubuntu Mono fallback

## Requirements

- macOS 14 or later
- Swift 5.10 or later

## Run

```sh
./script/build_and_run.sh
```

The app stores notes in `~/Documents/minute/`. Use **File → Reveal Notes
Folder** to open the library in Finder. Changes made by another text editor are
loaded when minute becomes active or with `⇧⌘R`.

On first launch, existing data from
`~/Library/Application Support/minute/library.json` (or the previous Cards
location) is copied into Markdown files. The original JSON file is retained as
a backup.

## Keyboard shortcuts

- `⌘N` — new note
- `⌘F` — focus note search
- `Escape` — move from search or the editor to the note index
- `↑` / `↓` — navigate notes or completion suggestions
- `Return` / `Tab` — insert the selected `@` suggestion
- `Tab` / `⇧Tab` in a list — indent or outdent the item
- `⌘⌫` — move the selected note to Trash
- `⇧⌘Z` — undo the most recent note deletion
- `⇧⌘L` — copy the selected note's full reference
- `⇧⌘R` — reload notes from disk

Type `@` followed by part of a timestamp or title. Choosing a result inserts a
reference such as `@202609130747 Progressive disclosure`; clicking it opens the
note. The timestamp is the stable link target, so the link continues to work if
the target title changes.

## Test and package

```sh
swift test
./script/package_release.sh 0.1.0
```

The package command creates a universal Apple Silicon/Intel, ad-hoc signed local
archive in `dist/`. See
[docs/RELEASING.md](docs/RELEASING.md) for Developer ID signing and Apple
notarization.

## License

MIT
