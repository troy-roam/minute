import SwiftUI

@MainActor
struct ArchiveEditorView: View {
    let library: LibraryStore
    let leaveEditor: () -> Void

    var body: some View {
        if let card = library.selectedCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("# \(card.timestampID)")
                        .fixedSize()

                    TextField("Untitled note", text: titleBinding)
                        .textFieldStyle(.plain)
                }
                .font(.jetBrainsMono(size: 18).bold())
                .foregroundStyle(.red)
                .padding(.horizontal, 42)
                .padding(.top, 42)
                .padding(.bottom, 22)

                RichNoteEditor(
                    rtfData: card.richTextRTF,
                    legacyMarkdown: editableBody(for: card),
                    suggestions: library.cards.map {
                        NoteLinkSuggestion(identifier: $0.timestampID, title: $0.title)
                    },
                    onChange: { data, markdown in
                        library.updateSelectedCard(richTextRTF: data, markdown: markdown)
                    },
                    onOpenCard: library.openCard,
                    onExitEditor: leaveEditor
                )
                    .padding(.horizontal, 36)
                    .padding(.bottom, 24)

                let backlinks = library.backlinks(to: card)
                if !backlinks.isEmpty {
                    Divider()
                    BacklinksView(
                        cards: backlinks,
                        openCard: library.openCard
                    )
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .id(card.id)
        } else {
            ContentUnavailableView {
                Label("No Note Selected", systemImage: "doc.text")
            } description: {
                Text("Select a note from the list or create a new one.")
            } actions: {
                Button("New Note", action: library.addCard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { library.selectedCard?.title ?? "" },
            set: { library.updateSelectedCard(title: $0) }
        )
    }

    private func editableBody(for card: NoteCard) -> String {
        let heading = "# \(card.title)"
        guard card.body == heading || card.body.hasPrefix(heading + "\n") else {
            return card.body
        }

        return String(card.body.dropFirst(heading.count))
            .trimmingCharacters(in: .newlines)
    }
}

private struct BacklinksView: View {
    let cards: [NoteCard]
    let openCard: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Backlinks")
                .foregroundStyle(.secondary)

            ForEach(cards) { card in
                Button {
                    openCard(card.timestampID)
                } label: {
                    Text("← \(card.name)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.jetBrainsMono(size: 11))
        .padding(.horizontal, 42)
        .padding(.vertical, 12)
        .frame(maxHeight: 130, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
}
