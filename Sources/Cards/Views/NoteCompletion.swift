import AppKit

struct NoteLinkSuggestion: Identifiable, Hashable {
    let identifier: String
    let title: String

    var id: String { identifier }

    var referenceText: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "@\(identifier)" : "@\(identifier) \(cleanTitle)"
    }
}

enum NoteLinkCompleter {
    struct Mention: Equatable {
        let query: String
        let range: NSRange
    }

    static func filtered(
        _ suggestions: [NoteLinkSuggestion],
        query: String,
        limit: Int = 8
    ) -> [NoteLinkSuggestion] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = term.isEmpty ? suggestions : suggestions.filter {
            $0.identifier.localizedCaseInsensitiveContains(term) ||
            $0.title.localizedCaseInsensitiveContains(term)
        }
        return Array(matches.prefix(limit))
    }

    static func activeMention(in text: String, cursor: Int) -> Mention? {
        let value = text as NSString
        guard cursor >= 0, cursor <= value.length else { return nil }
        let prefix = value.substring(with: NSRange(location: 0, length: cursor))
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])@([A-Za-z0-9-]*)$"#
        ),
        let match = regex.firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        ) else { return nil }

        return Mention(
            query: (prefix as NSString).substring(with: match.range(at: 1)),
            range: match.range
        )
    }
}

enum EditorListBehavior {
    struct Continuation: Equatable {
        let markerRange: NSRange
        let nextPrefix: String
        let itemIsEmpty: Bool
    }

    static func continuation(for paragraph: String, cursor: Int) -> Continuation? {
        let value = paragraph as NSString
        guard cursor >= 0, cursor <= value.length else { return nil }

        if let match = firstMatch(#"^([ \t]*)(☐|☑)[ \t]+"#, in: paragraph) {
            let indentation = value.substring(with: match.range(at: 1))
            return makeContinuation(
                value: value,
                match: match,
                cursor: cursor,
                nextPrefix: "\(indentation)☐ "
            )
        }

        if let match = firstMatch(#"^([ \t]*)(•|-|\*)[ \t]+"#, in: paragraph) {
            let indentation = value.substring(with: match.range(at: 1))
            let marker = value.substring(with: match.range(at: 2))
            return makeContinuation(
                value: value,
                match: match,
                cursor: cursor,
                nextPrefix: "\(indentation)\(marker) "
            )
        }

        if let match = firstMatch(#"^([ \t]*)(\d+)([.)])[ \t]+"#, in: paragraph) {
            let indentation = value.substring(with: match.range(at: 1))
            let number = Int(value.substring(with: match.range(at: 2))) ?? 0
            let delimiter = value.substring(with: match.range(at: 3))
            return makeContinuation(
                value: value,
                match: match,
                cursor: cursor,
                nextPrefix: "\(indentation)\(number + 1)\(delimiter) "
            )
        }

        return nil
    }

    static func leadingIndentRange(in paragraph: String) -> NSRange? {
        firstMatch(#"^[ \t]+"#, in: paragraph)?.range
    }

    private static func firstMatch(
        _ pattern: String,
        in value: String
    ) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (value as NSString).length)
        return try? NSRegularExpression(pattern: pattern).firstMatch(in: value, range: range)
    }

    private static func makeContinuation(
        value: NSString,
        match: NSTextCheckingResult,
        cursor: Int,
        nextPrefix: String
    ) -> Continuation {
        let contentRange = NSRange(
            location: NSMaxRange(match.range),
            length: value.length - NSMaxRange(match.range)
        )
        let content = value.substring(with: contentRange)
        let isAtEnd = cursor == value.length
        return Continuation(
            markerRange: match.range,
            nextPrefix: nextPrefix,
            itemIsEmpty: isAtEnd && content.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }
}

protocol NoteCompletionHandling: AnyObject {
    func handleCompletionKey(_ event: NSEvent) -> Bool
}

final class NoteCompletionPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu
        collectionBehavior = [.transient, .fullScreenAuxiliary]

        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.borderWidth = 0.5
        contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NoteCompletionTextView: NSTextView {
    weak var completionHandler: NoteCompletionHandling?

    override func keyDown(with event: NSEvent) {
        if completionHandler?.handleCompletionKey(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class NoteCompletionViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate {
    private let tableView = NSTableView()
    var onCommit: ((NoteLinkSuggestion) -> Void)?
    var suggestions: [NoteLinkSuggestion] = [] {
        didSet {
            tableView.reloadData()
            if !suggestions.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
            preferredContentSize = NSSize(
                width: 360,
                height: min(CGFloat(suggestions.count * 28 + 6), 230)
            )
        }
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(commitSelectedRow)
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))

        scrollView.documentView = tableView
        view = scrollView
        preferredContentSize = NSSize(width: 360, height: 34)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SuggestionCell")
        let cell: NoteSuggestionCell
        if let reused = tableView.makeView(
            withIdentifier: identifier,
            owner: self
        ) as? NoteSuggestionCell {
            cell = reused
        } else {
            cell = NoteSuggestionCell()
            cell.identifier = identifier
        }

        let suggestion = suggestions[row]
        cell.configure(with: suggestion)
        return cell
    }

    func moveSelection(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let destination = min(max(current + delta, 0), suggestions.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        tableView.scrollRowToVisible(destination)
    }

    func commitSelection() {
        let row = tableView.selectedRow
        guard suggestions.indices.contains(row) else { return }
        onCommit?(suggestions[row])
    }

    @objc private func commitSelectedRow() {
        commitSelection()
    }
}

private final class NoteSuggestionCell: NSTableCellView {
    private let identifierField = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for field in [identifierField, titleField] {
            field.font = .jetBrainsMono(size: 11)
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }

        NSLayoutConstraint.activate([
            identifierField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            identifierField.centerYAnchor.constraint(equalTo: centerYAnchor),
            identifierField.widthAnchor.constraint(equalToConstant: 104),
            titleField.leadingAnchor.constraint(equalTo: identifierField.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with suggestion: NoteLinkSuggestion) {
        identifierField.stringValue = "@\(suggestion.identifier)"
        titleField.stringValue = suggestion.title
    }
}
