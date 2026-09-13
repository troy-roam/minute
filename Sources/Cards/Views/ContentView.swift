import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var library: LibraryStore
    @State private var query = ""
    @FocusState private var searchIsFocused: Bool
    @FocusState private var noteListIsFocused: Bool

    private var visibleCards: [NoteCard] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return library.cards }

        if term.first == "@" {
            let reference = String(term.dropFirst())
            return library.cards.filter {
                $0.name.localizedCaseInsensitiveContains(reference)
            }
        }

        return library.cards.filter {
            $0.name.localizedCaseInsensitiveContains(term) ||
            $0.body.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                query: $query,
                canGoBackward: adjacentCard(offset: -1) != nil,
                canGoForward: adjacentCard(offset: 1) != nil,
                goBackward: { selectAdjacentCard(offset: -1) },
                goForward: { selectAdjacentCard(offset: 1) },
                addNote: library.addCard,
                isFocused: $searchIsFocused,
                leaveSearch: focusNoteList,
                openQuery: openQuery
            )

            Divider()

            GeometryReader { geometry in
                HSplitView {
                    NoteListPane(
                        cards: visibleCards,
                        isSearching: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        selection: Binding(
                            get: { library.selectedCardID },
                            set: { library.selectedCardID = $0 }
                        ),
                        isFocused: $noteListIsFocused,
                        deleteNote: library.deleteCard
                    )
                    .frame(
                        minWidth: 240,
                        idealWidth: 300,
                        maxWidth: 340,
                        maxHeight: .infinity
                    )

                    ArchiveEditorView(
                        library: library,
                        leaveEditor: focusNoteList
                    )
                    .frame(minWidth: 440, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("minute")
        .onReceive(NotificationCenter.default.publisher(for: .focusMinuteSearch)) { _ in
            searchIsFocused = true
        }
        .onChange(of: library.focusRequestID) {
            guard let requestedID = library.focusRequestID else { return }
            library.selectedCardID = requestedID
            library.focusRequestID = nil
        }
        .overlay(alignment: .bottom) {
            if let deletedNoteName = library.deletedNoteName {
                HStack(spacing: 12) {
                    Text("Moved \(deletedNoteName) to Trash")
                        .lineLimit(1)
                    Spacer()
                    Button("Undo", action: library.undoLastDelete)
                    Button {
                        library.deletedNoteName = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.jetBrainsMono(size: 11))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.bar)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: library.deletedNoteName)
        .alert("minute", isPresented: errorIsPresented) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "Unknown error")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reloadFromDisk()
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )
    }

    private func openQuery() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.first == "@" else { return }
        library.openCard(identifier: String(value.dropFirst()))
    }

    private func focusNoteList() {
        searchIsFocused = false
        noteListIsFocused = true
    }

    private func adjacentCard(offset: Int) -> NoteCard? {
        guard !visibleCards.isEmpty else { return nil }
        guard let selectedCardID = library.selectedCardID,
              let index = visibleCards.firstIndex(where: { $0.id == selectedCardID }) else {
            return offset > 0 ? visibleCards.first : nil
        }
        let destination = index + offset
        guard visibleCards.indices.contains(destination) else { return nil }
        return visibleCards[destination]
    }

    private func selectAdjacentCard(offset: Int) {
        library.selectedCardID = adjacentCard(offset: offset)?.id
    }
}

private struct SearchBar: View {
    @Binding var query: String
    let canGoBackward: Bool
    let canGoForward: Bool
    let goBackward: () -> Void
    let goForward: () -> Void
    let addNote: () -> Void
    @FocusState.Binding var isFocused: Bool
    let leaveSearch: () -> Void
    let openQuery: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button(action: goBackward) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBackward)

                Divider().frame(height: 18)

                Button(action: goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }
            .buttonStyle(.borderless)

            TextField("Search notes or enter @filename", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.jetBrainsMono(size: 12))
                .focused($isFocused)
                .onSubmit(openQuery)
                .onExitCommand(perform: leaveSearch)

            Button(action: addNote) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("New Note (⌘N)")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
    }
}

private struct NoteListPane: View {
    let cards: [NoteCard]
    let isSearching: Bool
    @Binding var selection: NoteCard.ID?
    @FocusState.Binding var isFocused: Bool
    let deleteNote: (NoteCard.ID) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(cards) { card in
                NoteListRow(card: card)
                    .tag(card.id)
                    .contextMenu {
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("@\(card.name)", forType: .string)
                        }

                        Divider()

                        Button("Delete Note", role: .destructive) {
                            deleteNote(card.id)
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .focused($isFocused)
        .overlay {
            if cards.isEmpty {
                if isSearching {
                    ContentUnavailableView.search
                } else {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "tray")
                    } description: {
                        Text("Create a new note with ⌘N.")
                    }
                }
            }
        }
    }
}

private struct NoteListRow: View {
    let card: NoteCard

    var body: some View {
        HStack(spacing: 6) {
            Text(card.timestampID)
                .font(.jetBrainsMono(size: 12))

            Text(card.title.isEmpty ? "Untitled note" : card.title)
                .font(.jetBrainsMono(size: 12))
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}
