# Contributing

minute is a SwiftPM macOS application targeting macOS 14 and later.

## Development

```sh
swift test
./script/build_and_run.sh
```

Keep the interface native and compact. SwiftUI owns application state and
layout; AppKit bridges should stay narrowly focused on text-system or window
behavior that SwiftUI cannot provide directly.

Notes must remain valid, portable UTF-8 Markdown files. Add tests for changes
to persistence, filename parsing, Markdown conversion, links, or editor
commands.
