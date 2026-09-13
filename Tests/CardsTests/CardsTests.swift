import AppKit
import Foundation
import Testing
@testable import Cards

@Suite("minute core behavior")
struct CardsTests {
    @Test("Timestamp IDs use a minute prefix and avoid collisions")
    func timestampIDs() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-13T07:47:00Z"))
        let first = TimestampID.make(at: date, excluding: [])
        let second = TimestampID.make(at: date, excluding: [first])

        #expect(first.count == 12)
        #expect(second == "\(first)-2")
    }

    @Test("Card names always begin with the timestamp identifier")
    func cardName() {
        let card = NoteCard(timestampID: "202609130747", title: "A useful note", accent: .blue)
        #expect(card.name == "202609130747 A useful note")
    }

    @Test("Card URLs resolve to their timestamp identifier")
    func links() throws {
        let url = try #require(URL(string: "card://202609130747"))
        #expect(MarkdownRenderer.cardIdentifier(from: url) == "202609130747")
    }

    @Test("Inline note links are highlighted and routed")
    @MainActor
    func inlineLinks() throws {
        let identifier = "202609130747"
        let title = "A useful note"
        let value = RichTextCodec.fromMarkdown("@\(identifier) \(title)")
        var openedIdentifier: String?
        let coordinator = RichNoteEditor.Coordinator(
            suggestions: [.init(identifier: identifier, title: title)],
            onChange: { _, _ in },
            onOpenCard: { openedIdentifier = $0 }
        )
        let textView = NSTextView()
        textView.textStorage?.setAttributedString(value)
        coordinator.decorateCardLinks(in: textView)
        let titleLocation = "@\(identifier) ".utf16.count
        let url = try #require(
            textView.textStorage?.attribute(.link, at: titleLocation, effectiveRange: nil) as? URL
        )

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: url,
            at: 0
        )

        #expect(handled)
        #expect(openedIdentifier == identifier)
    }

    @Test("Inline Markdown becomes formatting while typing")
    @MainActor
    func inlineMarkdownTyping() {
        let textView = NSTextView()
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: "A **bold** idea",
                attributes: [.font: NSFont.jetBrainsMono(size: 12)]
            )
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        let coordinator = RichNoteEditor.Coordinator(
            onChange: { _, _ in },
            onOpenCard: { _ in }
        )

        #expect(coordinator.applyInlineMarkdown(in: textView))
        #expect(textView.string == "A bold idea")

        let strokeWidth = textView.textStorage?.attribute(
            .strokeWidth,
            at: 3,
            effectiveRange: nil
        ) as? CGFloat
        #expect(strokeWidth == -2)
    }

    @Test("Note completion matches timestamp and title")
    func noteCompletion() {
        let suggestions = [
            NoteLinkSuggestion(identifier: "202609130747", title: "Progressive disclosure"),
            NoteLinkSuggestion(identifier: "202609130748", title: "A calm interface")
        ]

        #expect(
            NoteLinkCompleter.filtered(suggestions, query: "progressive")
                .map(\.identifier) == ["202609130747"]
        )
        #expect(
            NoteLinkCompleter.filtered(suggestions, query: "0748")
                .map(\.identifier) == ["202609130748"]
        )
        #expect(suggestions[0].referenceText == "@202609130747 Progressive disclosure")

        let text = "Connect this to @pro"
        #expect(
            NoteLinkCompleter.activeMention(in: text, cursor: text.utf16.count) ==
                .init(query: "pro", range: NSRange(location: 16, length: 4))
        )
        #expect(
            NoteLinkCompleter.activeMention(
                in: "Email me@example.com",
                cursor: "Email me@example.com".utf16.count
            ) == nil
        )
    }

    @Test("Return continues bullet and numbered lists")
    func listContinuation() throws {
        let bullet = try #require(
            EditorListBehavior.continuation(for: "• First item", cursor: 12)
        )
        #expect(bullet.nextPrefix == "• ")
        #expect(bullet.itemIsEmpty == false)

        let numbered = try #require(
            EditorListBehavior.continuation(for: "9. Ninth item", cursor: 13)
        )
        #expect(numbered.nextPrefix == "10. ")

        let empty = try #require(
            EditorListBehavior.continuation(for: "• ", cursor: 2)
        )
        #expect(empty.itemIsEmpty)

        let task = try #require(
            EditorListBehavior.continuation(for: "    ☐ Ship it", cursor: 13)
        )
        #expect(task.nextPrefix == "    ☐ ")
        #expect(
            EditorListBehavior.continuation(for: "☑ Done", cursor: 6)?.nextPrefix == "☐ "
        )
        #expect(EditorListBehavior.leadingIndentRange(in: "    • Nested")?.length == 4)
    }

    @Test("Completion panel aligns with the mention and stays on screen")
    @MainActor
    func completionAnchor() throws {
        let origin = RichNoteEditor.Coordinator.completionPanelOrigin(
            tokenRect: NSRect(x: 450, y: 500, width: 1, height: 16),
            panelSize: NSSize(width: 360, height: 118),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        #expect(origin.x == 450)
        #expect(origin.y == 378)
    }

    @Test("Escape from the note body leaves the editor")
    @MainActor
    func escapeLeavesEditor() {
        var didLeaveEditor = false
        let coordinator = RichNoteEditor.Coordinator(
            onChange: { _, _ in },
            onOpenCard: { _ in },
            onExitEditor: { didLeaveEditor = true }
        )

        let handled = coordinator.textView(
            NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )

        #expect(handled)
        #expect(didLeaveEditor)
    }

    @Test("Tab indents lists and Backspace removes a list marker")
    @MainActor
    func listEditingCommands() {
        let coordinator = RichNoteEditor.Coordinator(
            onChange: { _, _ in },
            onOpenCard: { _ in }
        )
        let textView = NSTextView()
        textView.string = "• Item"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        #expect(coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        ))
        #expect(textView.string == "    • Item")

        #expect(coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertBacktab(_:))
        ))
        #expect(textView.string == "• Item")

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))
        #expect(textView.string == "Item")
    }

    @Test("Legacy Markdown becomes editable rich text without visible syntax")
    func markdownMigration() {
        let value = RichTextCodec.fromMarkdown("# Heading\n\nA **bold** idea\n\n- One\n- Two")

        #expect(value.string == "Heading\n\nA bold idea\n\n• One\n• Two")
        #expect(value.string.contains("**") == false)
    }

    @Test("Rich text survives an RTF round trip")
    func richTextRoundTrip() throws {
        let original = RichTextCodec.fromMarkdown("Use *emphasis* here")
        let data = try #require(RichTextCodec.encode(original))
        let restored = try #require(RichTextCodec.decode(data))

        #expect(restored.string == "Use emphasis here")
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontName.contains("NF") == false)
    }
}
