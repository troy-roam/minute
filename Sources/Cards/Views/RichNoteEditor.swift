import AppKit
import SwiftUI

struct RichNoteEditor: NSViewRepresentable {
    let rtfData: Data?
    let legacyMarkdown: String
    let suggestions: [NoteLinkSuggestion]
    let onChange: (Data, String) -> Void
    let onOpenCard: (String) -> Void
    let onExitEditor: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            suggestions: suggestions,
            onChange: onChange,
            onOpenCard: onOpenCard,
            onExitEditor: onExitEditor
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NoteCompletionTextView()
        textView.delegate = context.coordinator
        textView.completionHandler = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .jetBrainsMono(size: 12)
        textView.typingAttributes = [
            .font: NSFont.jetBrainsMono(size: 12),
            .foregroundColor: NSColor.labelColor
        ]
        textView.textContainerInset = NSSize(width: 6, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let content = RichTextCodec.decode(rtfData) ?? RichTextCodec.fromMarkdown(legacyMarkdown)
        textView.textStorage?.setAttributedString(content)
        context.coordinator.decorateCardLinks(in: textView)
        context.coordinator.lastRTF = rtfData
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onOpenCard = onOpenCard
        context.coordinator.onExitEditor = onExitEditor
        context.coordinator.suggestions = suggestions

        guard let textView = scrollView.documentView as? NSTextView,
              let rtfData,
              rtfData != context.coordinator.lastRTF,
              let decoded = RichTextCodec.decode(rtfData) else { return }

        context.coordinator.isApplyingUpdate = true
        textView.textStorage?.setAttributedString(decoded)
        context.coordinator.decorateCardLinks(in: textView)
        context.coordinator.lastRTF = rtfData
        context.coordinator.isApplyingUpdate = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NoteCompletionHandling {
        var suggestions: [NoteLinkSuggestion]
        var onChange: (Data, String) -> Void
        var onOpenCard: (String) -> Void
        var onExitEditor: () -> Void
        var lastRTF: Data?
        var isApplyingUpdate = false
        private var mentionRange: NSRange?
        private weak var completionTextView: NSTextView?
        private let completionViewController = NoteCompletionViewController()
        private lazy var completionPanel = NoteCompletionPanel(
            contentViewController: completionViewController
        )

        init(
            suggestions: [NoteLinkSuggestion] = [],
            onChange: @escaping (Data, String) -> Void,
            onOpenCard: @escaping (String) -> Void,
            onExitEditor: @escaping () -> Void = {}
        ) {
            self.suggestions = suggestions
            self.onChange = onChange
            self.onOpenCard = onOpenCard
            self.onExitEditor = onExitEditor
            super.init()
            completionViewController.onCommit = { [weak self] suggestion in
                self?.insert(suggestion)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? NSTextView else { return }
            isApplyingUpdate = true
            applyInlineMarkdown(in: textView)
            decorateCardLinks(in: textView)
            isApplyingUpdate = false
            deliver(textView)
            updateCompletions(in: textView)
        }

        func handleCompletionKey(_ event: NSEvent) -> Bool {
            guard completionPanel.isVisible else { return false }
            switch event.keyCode {
            case 125:
                completionViewController.moveSelection(by: 1)
            case 126:
                completionViewController.moveSelection(by: -1)
            case 36, 48:
                completionViewController.commitSelection()
            case 53:
                dismissCompletions()
                onExitEditor()
            default:
                return false
            }
            return true
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                dismissCompletions()
                onExitEditor()
                return true
            case #selector(NSResponder.insertTab(_:)):
                return adjustListIndent(in: textView, increase: true)
            case #selector(NSResponder.insertBacktab(_:)):
                return adjustListIndent(in: textView, increase: false)
            case #selector(NSResponder.deleteBackward(_:)):
                return handleListBackspace(in: textView)
            default:
                return false
            }
        }

        private func updateCompletions(in textView: NSTextView) {
            guard let mention = activeMention(in: textView) else {
                dismissCompletions()
                return
            }

            let matches = NoteLinkCompleter.filtered(suggestions, query: mention.query)
            guard !matches.isEmpty else {
                dismissCompletions()
                return
            }

            mentionRange = mention.range
            completionTextView = textView
            completionViewController.suggestions = matches
            showCompletionPanel(for: mention.range, in: textView)
        }

        private func showCompletionPanel(for mentionRange: NSRange, in textView: NSTextView) {
            guard let parentWindow = textView.window else { return }
            var actualRange = NSRange()
            let tokenRect = textView.firstRect(
                forCharacterRange: NSRange(location: mentionRange.location, length: 0),
                actualRange: &actualRange
            )
            let size = completionViewController.preferredContentSize
            completionPanel.setContentSize(size)

            let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let origin = Self.completionPanelOrigin(
                tokenRect: tokenRect,
                panelSize: size,
                visibleFrame: visibleFrame
            )
            completionPanel.setFrameOrigin(origin)

            if completionPanel.parent !== parentWindow {
                completionPanel.parent?.removeChildWindow(completionPanel)
                parentWindow.addChildWindow(completionPanel, ordered: .above)
            }
            completionPanel.orderFront(nil)
            parentWindow.makeFirstResponder(textView)
        }

        static func completionPanelOrigin(
            tokenRect: NSRect,
            panelSize: NSSize,
            visibleFrame: NSRect
        ) -> NSPoint {
            var origin = NSPoint(
                x: tokenRect.minX,
                y: tokenRect.minY - panelSize.height - 4
            )
            if origin.y < visibleFrame.minY {
                origin.y = tokenRect.maxY + 4
            }
            origin.x = min(
                max(origin.x, visibleFrame.minX + 4),
                visibleFrame.maxX - panelSize.width - 4
            )
            return origin
        }

        private func activeMention(in textView: NSTextView) -> (
            query: String,
            range: NSRange
        )? {
            guard let mention = NoteLinkCompleter.activeMention(
                in: textView.string,
                cursor: textView.selectedRange().location
            ) else { return nil }
            return (mention.query, mention.range)
        }

        private func insert(_ suggestion: NoteLinkSuggestion) {
            guard let textView = completionTextView,
                  let mentionRange else { return }
            let replacement = suggestion.referenceText
            guard textView.shouldChangeText(
                in: mentionRange,
                replacementString: replacement
            ) else { return }

            textView.textStorage?.replaceCharacters(
                in: mentionRange,
                with: replacement
            )
            textView.setSelectedRange(
                NSRange(location: mentionRange.location + replacement.utf16.count, length: 0)
            )
            textView.didChangeText()
            dismissCompletions()
            textView.window?.makeFirstResponder(textView)
        }

        private func dismissCompletions() {
            mentionRange = nil
            completionTextView = nil
            completionPanel.parent?.removeChildWindow(completionPanel)
            completionPanel.orderOut(nil)
        }

        @discardableResult
        func applyInlineMarkdown(in textView: NSTextView) -> Bool {
            var changed = false
            changed = replaceInlinePattern(
                #"\*\*([^*\n]+)\*\*"#,
                in: textView,
                markerLength: 4,
                strokeWidth: -2
            ) { font in
                NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            } || changed
            changed = replaceInlinePattern(
                #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
                in: textView,
                markerLength: 2
            ) { font in
                NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            } || changed
            changed = replaceInlinePattern(
                #"`([^`\n]+)`"#,
                in: textView,
                markerLength: 2,
                backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
            ) { font in
                NSFont.jetBrainsMono(size: font.pointSize * 0.94)
            } || changed
            return changed
        }

        private func replaceInlinePattern(
            _ pattern: String,
            in textView: NSTextView,
            markerLength: Int,
            backgroundColor: NSColor? = nil,
            strokeWidth: CGFloat? = nil,
            transformFont: (NSFont) -> NSFont
        ) -> Bool {
            guard let storage = textView.textStorage,
                  let regex = try? NSRegularExpression(pattern: pattern) else { return false }

            let matches = regex.matches(
                in: storage.string,
                range: NSRange(location: 0, length: storage.length)
            )
            guard !matches.isEmpty else { return false }

            var selection = textView.selectedRange()
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                let replacement = NSMutableAttributedString(
                    attributedString: storage.attributedSubstring(from: contentRange)
                )
                let sourceFont = replacement.attribute(
                    .font,
                    at: 0,
                    effectiveRange: nil
                ) as? NSFont ?? .jetBrainsMono(size: 12)
                let replacementRange = NSRange(location: 0, length: replacement.length)
                replacement.addAttribute(
                    .font,
                    value: transformFont(sourceFont),
                    range: replacementRange
                )
                if let backgroundColor {
                    replacement.addAttribute(
                        .backgroundColor,
                        value: backgroundColor,
                        range: replacementRange
                    )
                }
                if let strokeWidth {
                    replacement.addAttribute(
                        .strokeWidth,
                        value: strokeWidth,
                        range: replacementRange
                    )
                }

                storage.replaceCharacters(in: match.range, with: replacement)

                if NSMaxRange(match.range) <= selection.location {
                    selection.location -= markerLength
                } else if selection.location > match.range.location {
                    selection.location = match.range.location + replacement.length
                    selection.length = 0
                }
            }
            textView.setSelectedRange(selection)
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if replacementString == "\n",
               handleListReturn(in: textView, affectedRange: affectedCharRange) {
                return false
            }

            guard replacementString == " ", affectedCharRange.length == 0 else { return true }

            let source = textView.string as NSString
            let paragraphRange = source.paragraphRange(for: NSRange(location: affectedCharRange.location, length: 0))
            let prefixRange = NSRange(location: paragraphRange.location, length: affectedCharRange.location - paragraphRange.location)
            let prefix = source.substring(with: prefixRange)

            let attributes: [NSAttributedString.Key: Any]?
            switch prefix {
            case "#":
                attributes = [.font: boldFont(size: 18)]
            case "##":
                attributes = [.font: boldFont(size: 16)]
            case "###":
                attributes = [.font: boldFont(size: 14)]
            case "-", "*":
                textView.textStorage?.replaceCharacters(in: prefixRange, with: "•")
                textView.setSelectedRange(NSRange(location: affectedCharRange.location, length: 0))
                return true
            case "- [ ]":
                textView.insertText("☐ ", replacementRange: prefixRange)
                return false
            case "- [x]", "- [X]":
                textView.insertText("☑ ", replacementRange: prefixRange)
                return false
            case ">":
                attributes = [
                    .font: NSFont.jetBrainsMono(size: 12),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .obliqueness: 0.16
                ]
            default:
                return true
            }

            textView.textStorage?.deleteCharacters(in: prefixRange)
            textView.typingAttributes = attributes ?? [:]
            textView.setSelectedRange(NSRange(location: paragraphRange.location, length: 0))
            deliver(textView)
            return false
        }

        private func handleListReturn(
            in textView: NSTextView,
            affectedRange: NSRange
        ) -> Bool {
            let source = textView.string as NSString
            let cursor = min(affectedRange.location, source.length)
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: cursor, length: 0)
            )
            var contentLength = paragraphRange.length
            while contentLength > 0 {
                let character = source.character(at: paragraphRange.location + contentLength - 1)
                guard character == 10 || character == 13 else { break }
                contentLength -= 1
            }
            let contentRange = NSRange(location: paragraphRange.location, length: contentLength)
            let paragraph = source.substring(with: contentRange)
            let relativeCursor = cursor - paragraphRange.location
            guard let continuation = EditorListBehavior.continuation(
                for: paragraph,
                cursor: relativeCursor
            ) else { return false }

            if continuation.itemIsEmpty {
                let markerRange = NSRange(
                    location: paragraphRange.location + continuation.markerRange.location,
                    length: continuation.markerRange.length
                )
                textView.insertText("", replacementRange: markerRange)
            } else {
                textView.insertText(
                    "\n\(continuation.nextPrefix)",
                    replacementRange: affectedRange
                )
            }
            return true
        }

        private func adjustListIndent(
            in textView: NSTextView,
            increase: Bool
        ) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            let cursor = min(selection.location, source.length)
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: cursor, length: 0)
            )
            let paragraph = source.substring(with: paragraphRange)
                .trimmingCharacters(in: .newlines)
            guard EditorListBehavior.continuation(
                for: paragraph,
                cursor: min(cursor - paragraphRange.location, (paragraph as NSString).length)
            ) != nil else { return false }

            if increase {
                textView.insertText(
                    "    ",
                    replacementRange: NSRange(location: paragraphRange.location, length: 0)
                )
                textView.setSelectedRange(
                    NSRange(location: selection.location + 4, length: selection.length)
                )
                return true
            }

            guard let indentRange = EditorListBehavior.leadingIndentRange(in: paragraph) else {
                return false
            }
            let indentation = (paragraph as NSString).substring(with: indentRange)
            let removeCount = indentation.hasPrefix("\t") ? 1 : min(4, indentation.utf16.count)
            textView.insertText(
                "",
                replacementRange: NSRange(location: paragraphRange.location, length: removeCount)
            )
            textView.setSelectedRange(
                NSRange(
                    location: max(paragraphRange.location, selection.location - removeCount),
                    length: selection.length
                )
            )
            return true
        }

        private func handleListBackspace(in textView: NSTextView) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location > 0 else { return false }
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: selection.location, length: 0)
            )
            let paragraph = source.substring(with: paragraphRange)
                .trimmingCharacters(in: .newlines)
            let relativeCursor = selection.location - paragraphRange.location
            guard let continuation = EditorListBehavior.continuation(
                for: paragraph,
                cursor: min(relativeCursor, (paragraph as NSString).length)
            ), relativeCursor == NSMaxRange(continuation.markerRange) else { return false }

            if let indentRange = EditorListBehavior.leadingIndentRange(in: paragraph) {
                let indentation = (paragraph as NSString).substring(with: indentRange)
                let removeCount = indentation.hasPrefix("\t") ? 1 : min(4, indentation.utf16.count)
                textView.insertText(
                    "",
                    replacementRange: NSRange(location: paragraphRange.location, length: removeCount)
                )
                textView.setSelectedRange(
                    NSRange(location: selection.location - removeCount, length: 0)
                )
            } else {
                textView.insertText(
                    "",
                    replacementRange: NSRange(
                        location: paragraphRange.location,
                        length: continuation.markerRange.length
                    )
                )
                textView.setSelectedRange(NSRange(location: paragraphRange.location, length: 0))
            }
            return true
        }

        private func boldFont(size: CGFloat) -> NSFont {
            NSFontManager.shared.convert(
                NSFont.jetBrainsMono(size: size),
                toHaveTrait: .boldFontMask
            )
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url, let identifier = MarkdownRenderer.cardIdentifier(from: url) else { return false }
            onOpenCard(identifier)
            return true
        }

        func decorateCardLinks(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)

            storage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
                let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                if url?.scheme == "card" {
                    storage.removeAttribute(.link, range: range)
                    storage.removeAttribute(.underlineStyle, range: range)
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            }

            let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9])@(\d{12}(?:-\d+)?)"#)
            regex?.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
                guard let match else { return }
                let identifier = (storage.string as NSString).substring(with: match.range(at: 1))
                storage.addAttributes([
                    .link: URL(string: "card://\(identifier)") as Any,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            }


            for suggestion in suggestions where !suggestion.title.isEmpty {
                let token = suggestion.referenceText
                var cursor = 0
                while cursor < storage.length {
                    let remaining = NSRange(location: cursor, length: storage.length - cursor)
                    let match = (storage.string as NSString).range(of: token, range: remaining)
                    guard match.location != NSNotFound else { break }
                    storage.addAttributes([
                        .link: URL(string: "card://\(suggestion.identifier)") as Any,
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], range: match)
                    cursor = NSMaxRange(match)
                }
            }
        }

        private func deliver(_ textView: NSTextView) {
            guard let storage = textView.textStorage,
                  let data = RichTextCodec.encode(storage) else { return }
            lastRTF = data
            onChange(data, RichTextCodec.toMarkdown(storage))
        }
    }
}

enum RichTextCodec {
    static func decode(_ data: Data?) -> NSAttributedString? {
        guard let data else { return nil }
        guard let decoded = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }

        let fullRange = NSRange(location: 0, length: decoded.length)
        decoded.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let source = value as? NSFont else { return }
            var replacement = NSFont.jetBrainsMono(size: source.pointSize)
            let traits = source.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                replacement = NSFontManager.shared.convert(replacement, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italic) {
                replacement = NSFontManager.shared.convert(replacement, toHaveTrait: .italicFontMask)
            }
            decoded.addAttribute(.font, value: replacement, range: range)
        }
        return decoded
    }

    static func encode(_ value: NSAttributedString) -> Data? {
        try? value.data(
            from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func toMarkdown(_ value: NSAttributedString) -> String {
        let source = value.string as NSString
        var output: [String] = []
        var location = 0

        while location <= source.length {
            if location == source.length {
                if source.length == 0 || source.hasSuffix("\n") { output.append("") }
                break
            }

            let paragraphRange = source.paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            var contentLength = paragraphRange.length
            while contentLength > 0 {
                let character = source.character(at: paragraphRange.location + contentLength - 1)
                guard character == 10 || character == 13 else { break }
                contentLength -= 1
            }
            let lineRange = NSRange(location: paragraphRange.location, length: contentLength)
            output.append(markdownLine(from: value, range: lineRange))
            location = NSMaxRange(paragraphRange)
        }

        return output.joined(separator: "\n")
    }

    private static func markdownLine(
        from value: NSAttributedString,
        range: NSRange
    ) -> String {
        guard range.length > 0 else { return "" }
        let source = value.string as NSString
        let line = source.substring(with: range) as NSString
        var contentRange = range
        var prefix = ""
        var suppressBold = false
        var suppressItalic = false

        let leadingWhitespace = line.range(of: #"^[ \t]*"#, options: .regularExpression)
        let indentation = line.substring(with: leadingWhitespace)
        let markerLocation = range.location + leadingWhitespace.length
        let remainderRange = NSRange(
            location: leadingWhitespace.length,
            length: line.length - leadingWhitespace.length
        )
        let remainder = line.substring(with: remainderRange)

        if remainder.hasPrefix("• ") {
            prefix = indentation + "- "
            contentRange.location = markerLocation + 2
            contentRange.length = NSMaxRange(range) - contentRange.location
        } else if remainder.hasPrefix("☐ ") {
            prefix = indentation + "- [ ] "
            contentRange.location = markerLocation + 2
            contentRange.length = NSMaxRange(range) - contentRange.location
        } else if remainder.hasPrefix("☑ ") {
            prefix = indentation + "- [x] "
            contentRange.location = markerLocation + 2
            contentRange.length = NSMaxRange(range) - contentRange.location
        } else {
            let font = value.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let size = font?.pointSize ?? 12
            if size >= 17 {
                prefix = "# "
                suppressBold = true
            } else if size >= 15 {
                prefix = "## "
                suppressBold = true
            } else if size >= 13 {
                prefix = "### "
                suppressBold = true
            } else if let color = value.attribute(
                .foregroundColor,
                at: range.location,
                effectiveRange: nil
            ) as? NSColor,
                color == NSColor.secondaryLabelColor {
                prefix = "> "
                suppressItalic = true
            }
        }

        return prefix + inlineMarkdown(
            from: value,
            range: contentRange,
            suppressBold: suppressBold,
            suppressItalic: suppressItalic
        )
    }

    private static func inlineMarkdown(
        from value: NSAttributedString,
        range: NSRange,
        suppressBold: Bool = false,
        suppressItalic: Bool = false
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        value.enumerateAttributes(in: range) { attributes, attributeRange, _ in
            let clipped = NSIntersectionRange(range, attributeRange)
            guard clipped.length > 0 else { return }
            let text = (value.string as NSString).substring(with: clipped)
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isCode = attributes[.backgroundColor] != nil
            let isBold = !suppressBold && (
                traits.contains(.bold) || (attributes[.strokeWidth] as? CGFloat ?? 0) < 0
            )
            let isItalic = !suppressItalic && (
                traits.contains(.italic) || (attributes[.obliqueness] as? CGFloat ?? 0) != 0
            )

            if isCode {
                result += "`\(text)`"
            } else if isBold && isItalic {
                result += "***\(text)***"
            } else if isBold {
                result += "**\(text)**"
            } else if isItalic {
                result += "*\(text)*"
            } else {
                result += text
            }
        }
        return result
    }

    static func fromMarkdown(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)

        for (index, rawLine) in lines.enumerated() {
            let indentation = String(rawLine.prefix { $0 == " " || $0 == "\t" })
            var line = String(rawLine.dropFirst(indentation.count))
            var visibleIndentation = indentation
            var font = NSFont.jetBrainsMono(size: 12)
            var color = NSColor.labelColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 7

            if line.hasPrefix("### ") {
                line.removeFirst(4)
                visibleIndentation = ""
                font = boldFont(size: 14)
                paragraph.paragraphSpacing = 9
            } else if line.hasPrefix("## ") {
                line.removeFirst(3)
                visibleIndentation = ""
                font = boldFont(size: 16)
                paragraph.paragraphSpacing = 10
            } else if line.hasPrefix("# ") {
                line.removeFirst(2)
                visibleIndentation = ""
                font = boldFont(size: 18)
                paragraph.paragraphSpacing = 12
            } else if line.hasPrefix("- [ ] ") {
                line = "☐ " + line.dropFirst(6)
                paragraph.headIndent = CGFloat(indentation.count * 7 + 20)
            } else if line.lowercased().hasPrefix("- [x] ") {
                line = "☑ " + line.dropFirst(6)
                paragraph.headIndent = CGFloat(indentation.count * 7 + 20)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
                paragraph.headIndent = CGFloat(indentation.count * 7 + 20)
            } else if line.hasPrefix("> ") {
                line.removeFirst(2)
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                color = .secondaryLabelColor
                paragraph.headIndent = 16
            }

            line = visibleIndentation + line

            let lineStart = result.length
            appendInline(line, to: result, font: font, color: color)
            let lineRange = NSRange(location: lineStart, length: result.length - lineStart)
            result.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]))
            }
        }
        return result
    }

    private static func appendInline(
        _ source: String,
        to result: NSMutableAttributedString,
        font: NSFont,
        color: NSColor
    ) {
        let pattern = #"\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*|(?<![A-Za-z0-9])@\d{12}(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            result.append(NSAttributedString(string: source, attributes: [.font: font, .foregroundColor: color]))
            return
        }

        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        var cursor = 0

        func append(_ text: String, attributes: [NSAttributedString.Key: Any]) {
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        for match in matches {
            if match.range.location > cursor {
                append(nsSource.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), attributes: [
                    .font: font,
                    .foregroundColor: color
                ])
            }

            let token = nsSource.substring(with: match.range)
            if token.hasPrefix("**") {
                let text = String(token.dropFirst(2).dropLast(2))
                append(text, attributes: [
                    .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
                    .foregroundColor: color,
                    .strokeWidth: -2
                ])
            } else if token.hasPrefix("`") {
                append(String(token.dropFirst().dropLast()), attributes: [
                    .font: NSFont.jetBrainsMono(size: font.pointSize * 0.94),
                    .foregroundColor: color,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                ])
            } else if token.hasPrefix("*") {
                append(String(token.dropFirst().dropLast()), attributes: [
                    .font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask),
                    .foregroundColor: color
                ])
            } else {
                let identifier = String(token.dropFirst())
                append(token, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: URL(string: "card://\(identifier)") as Any
                ])
            }
            cursor = NSMaxRange(match.range)
        }

        if cursor < nsSource.length {
            append(nsSource.substring(from: cursor), attributes: [.font: font, .foregroundColor: color])
        }
    }

    private static func boldFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(
            NSFont.jetBrainsMono(size: size),
            toHaveTrait: .boldFontMask
        )
    }
}
