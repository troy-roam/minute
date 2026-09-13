import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var cards: [NoteCard]
    var selectedCardID: NoteCard.ID?
    var focusRequestID: NoteCard.ID?
    var lastError: String?
    var deletedNoteName: String?

    let notesDirectoryURL: URL

    private let library: MarkdownLibrary
    private var deletedNote: (card: NoteCard, trashURL: URL, originalURL: URL)?

    var selectedCard: NoteCard? {
        guard let selectedCardID else { return nil }
        return cards.first { $0.id == selectedCardID }
    }

    init(
        notesDirectoryURL: URL? = nil,
        legacyPersistenceURL: URL? = nil,
        seedSampleData: Bool = true,
        trashDirectoryURL: URL? = nil
    ) {
        let directory = notesDirectoryURL ?? Self.defaultNotesDirectoryURL
        let directoryExisted = FileManager.default.fileExists(atPath: directory.path)
        self.notesDirectoryURL = directory
        library = MarkdownLibrary(
            directoryURL: directory,
            trashDirectoryURL: trashDirectoryURL
        )
        cards = []
        selectedCardID = nil
        focusRequestID = nil

        do {
            try library.createDirectoryIfNeeded()
            cards = try library.load()
            if cards.isEmpty && !directoryExisted {
                let migrationURL = legacyPersistenceURL
                    ?? (notesDirectoryURL == nil ? Self.existingLegacyPersistenceURL : nil)
                if let migrationURL {
                    cards = try Self.migrateLegacyLibrary(from: migrationURL, into: library)
                }
                if cards.isEmpty && seedSampleData {
                    cards = try Self.seedSamples(into: library)
                }
            }
        } catch {
            lastError = "Could not open the note library: \(error.localizedDescription)"
        }

        selectedCardID = cards.first?.id
    }

    func addCard() {
        let existing = Set(cards.map(\.timestampID))
        let identifier = TimestampID.make(excluding: existing)
        var card = NoteCard(
            timestampID: identifier,
            title: "Untitled note",
            body: "Start writing.",
            accent: CardAccent.allCases[cards.count % CardAccent.allCases.count]
        )
        do {
            card.fileURL = try library.save(card)
            cards.append(card)
            selectedCardID = card.id
            focusRequestID = card.id
        } catch {
            report("Could not create the note", error: error)
        }
    }

    func updateSelectedCard(title: String? = nil, body: String? = nil) {
        guard let index = selectedCardIndex else { return }
        let previousURL = cards[index].fileURL
        if let title { cards[index].title = title }
        if let body { cards[index].body = body }
        cards[index].updatedAt = .now
        saveCard(at: index, replacing: previousURL)
    }

    func updateSelectedCard(richTextRTF: Data, markdown: String) {
        guard let index = selectedCardIndex else { return }
        cards[index].richTextRTF = richTextRTF
        cards[index].body = markdown
        cards[index].updatedAt = .now
        saveCard(at: index, replacing: cards[index].fileURL)
    }

    func deleteSelectedCard() {
        guard let selectedCardID else { return }
        deleteCard(selectedCardID)
    }

    func deleteCard(_ id: NoteCard.ID) {
        guard let index = cards.firstIndex(where: { $0.id == id }),
              let originalURL = cards[index].fileURL else { return }
        let card = cards[index]
        do {
            let trashURL = try library.moveToTrash(card)
            deletedNote = (card, trashURL, originalURL)
            deletedNoteName = card.name
            cards.remove(at: index)
            selectedCardID = cards.indices.contains(index) ? cards[index].id : cards.last?.id
        } catch {
            report("Could not move the note to Trash", error: error)
        }
    }

    func undoLastDelete() {
        guard let deletion = deletedNote else { return }
        do {
            try library.restoreFromTrash(deletion.trashURL, to: deletion.originalURL)
            var card = deletion.card
            card.fileURL = deletion.originalURL
            cards.append(card)
            cards.sort { $0.timestampID < $1.timestampID }
            selectedCardID = card.id
            deletedNote = nil
            deletedNoteName = nil
        } catch {
            report("Could not restore the note", error: error)
        }
    }

    func reloadFromDisk() {
        let selectedIdentifier = selectedCard?.timestampID
        do {
            cards = try library.load()
            selectedCardID = cards.first(where: { $0.timestampID == selectedIdentifier })?.id
                ?? cards.first?.id
        } catch {
            report("Could not reload the note library", error: error)
        }
    }

    func revealNotesFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: notesDirectoryURL.path)
    }

    func openCard(identifier: String) {
        let stableIdentifier = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? identifier
        guard let card = cards.first(where: { $0.timestampID == stableIdentifier }) else {
            NSSound.beep()
            return
        }
        selectedCardID = card.id
        focusRequestID = card.id
    }

    func backlinks(to card: NoteCard) -> [NoteCard] {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9])@\(NSRegularExpression.escapedPattern(for: card.timestampID))(?=$|[^A-Za-z0-9-])"
        ) else { return [] }
        return cards.filter { candidate in
            guard candidate.id != card.id else { return false }
            let range = NSRange(location: 0, length: (candidate.body as NSString).length)
            return regex.firstMatch(in: candidate.body, range: range) != nil
        }
    }

    func copySelectedCardLink() {
        guard let selectedCard else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("@\(selectedCard.name)", forType: .string)
    }

    private var selectedCardIndex: Int? {
        guard let selectedCardID else { return nil }
        return cards.firstIndex { $0.id == selectedCardID }
    }

    private func saveCard(at index: Int, replacing previousURL: URL?) {
        do {
            cards[index].fileURL = try library.save(cards[index], replacing: previousURL)
        } catch {
            report("Could not save the note", error: error)
        }
    }

    private func report(_ message: String, error: Error) {
        lastError = "\(message): \(error.localizedDescription)"
    }

    private static var defaultNotesDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("minute", isDirectory: true)
    }

    private static var existingLegacyPersistenceURL: URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let minuteURL = support.appendingPathComponent("minute/library.json")
        if FileManager.default.fileExists(atPath: minuteURL.path) { return minuteURL }
        let cardsURL = support.appendingPathComponent("Cards/library.json")
        return FileManager.default.fileExists(atPath: cardsURL.path) ? cardsURL : nil
    }

    private static func migrateLegacyLibrary(
        from url: URL,
        into library: MarkdownLibrary
    ) throws -> [NoteCard] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decodedCards: [NoteCard]
        if let cards = try? JSONDecoder().decode([NoteCard].self, from: data) {
            decodedCards = cards
        } else if let lists = try? JSONDecoder().decode([NoteList].self, from: data) {
            decodedCards = lists.flatMap(\.cards)
        } else {
            return []
        }

        var migrated: [NoteCard] = []
        for var card in decodedCards {
            if let richText = RichTextCodec.decode(card.richTextRTF) {
                card.body = RichTextCodec.toMarkdown(richText)
            }
            card.richTextRTF = nil
            card.fileURL = try library.save(card)
            migrated.append(card)
        }
        return migrated.sorted { $0.timestampID < $1.timestampID }
    }

    private static func seedSamples(into library: MarkdownLibrary) throws -> [NoteCard] {
        var cards = sampleCards()
        for index in cards.indices {
            cards[index].fileURL = try library.save(cards[index])
        }
        return cards
    }

    private static func sampleCards() -> [NoteCard] {
        let now = Date.now
        let calendar = Calendar.current
        let dates = (-3...0).map {
            calendar.date(byAdding: .minute, value: $0 * 2, to: now) ?? now
        }
        var used = Set<String>()
        let identifiers = dates.map { date in
            let identifier = TimestampID.make(at: date, excluding: used)
            used.insert(identifier)
            return identifier
        }

        return [
            NoteCard(
                timestampID: identifiers[0],
                title: "Make the state visible",
                body: "A good interface shows people **where they are**, what changed, and what they can do next.\n\n- Prefer direct manipulation\n- Keep primary actions nearby\n- Let motion explain hierarchy",
                accent: .blue,
                createdAt: dates[0],
                updatedAt: dates[0]
            ),
            NoteCard(
                timestampID: identifiers[1],
                title: "Progressive disclosure",
                body: "Show the essentials first. Reveal detail when it becomes useful.\n\nThis builds on @\(identifiers[0]) Make the state visible.",
                accent: .indigo,
                createdAt: dates[1],
                updatedAt: dates[1]
            ),
            NoteCard(
                timestampID: identifiers[2],
                title: "A calm interface",
                body: "> Simplicity is not the absence of capability. It is clarity about what matters now.\n\nUse spacing, type, and hierarchy before adding decoration.",
                accent: .plum,
                createdAt: dates[2],
                updatedAt: dates[2]
            ),
            NoteCard(
                timestampID: identifiers[3],
                title: "Plan the week",
                body: "- [ ] Choose three priorities\n- [ ] Protect focus time\n- [ ] Review on Friday",
                accent: .orange,
                createdAt: dates[3],
                updatedAt: dates[3]
            )
        ]
    }
}
