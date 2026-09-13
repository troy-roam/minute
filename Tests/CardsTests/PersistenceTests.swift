import AppKit
import Foundation
import Testing
@testable import Cards

@Suite("Markdown library")
struct PersistenceTests {
    @Test("Markdown notes save, rename, and reload")
    func saveRenameReload() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MarkdownLibrary(directoryURL: root)
        var card = NoteCard(
            timestampID: "202609132130",
            title: "First title",
            body: "A **portable** note.",
            accent: .blue
        )
        let firstURL = try library.save(card)
        card.fileURL = firstURL
        card.title = "Renamed title"
        let renamedURL = try library.save(card, replacing: firstURL)

        #expect(FileManager.default.fileExists(atPath: firstURL.path) == false)
        #expect(renamedURL.lastPathComponent == "202609132130 Renamed title.md")
        let loaded = try #require(library.load().first)
        #expect(loaded.title == "Renamed title")
        #expect(loaded.body == "A **portable** note.")
    }

    @Test("Rich editing round-trips to portable Markdown")
    func markdownRoundTrip() {
        let markdown = "# Heading\n\nA **bold** and *quiet* thought.\n\n- [ ] Task\n    - Nested"
        let richText = RichTextCodec.fromMarkdown(markdown)
        #expect(RichTextCodec.toMarkdown(richText) == markdown)
    }

    @Test("Legacy JSON is copied into Markdown files")
    @MainActor
    func legacyMigration() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesURL = root.appendingPathComponent("notes")
        let legacyURL = root.appendingPathComponent("library.json")
        let richText = RichTextCodec.fromMarkdown("A **migrated** note")
        let legacyCard = NoteCard(
            timestampID: "202609132131",
            title: "Migration",
            body: "stale body",
            richTextRTF: RichTextCodec.encode(richText),
            accent: .indigo
        )
        try JSONEncoder().encode([legacyCard]).write(to: legacyURL, options: .atomic)

        let store = LibraryStore(
            notesDirectoryURL: notesURL,
            legacyPersistenceURL: legacyURL,
            seedSampleData: false
        )

        #expect(store.cards.count == 1)
        #expect(store.cards[0].body == "A **migrated** note")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(FileManager.default.fileExists(
            atPath: notesURL.appendingPathComponent("202609132131 Migration.md").path
        ))
    }

    @Test("Deletion is recoverable")
    @MainActor
    func trashAndUndo() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesURL = root.appendingPathComponent("notes")
        let trashURL = root.appendingPathComponent("trash")
        let store = LibraryStore(
            notesDirectoryURL: notesURL,
            seedSampleData: false,
            trashDirectoryURL: trashURL
        )
        store.addCard()
        let originalURL = try #require(store.selectedCard?.fileURL)

        store.deleteSelectedCard()
        #expect(store.cards.isEmpty)
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)

        store.undoLastDelete()
        #expect(store.cards.count == 1)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
    }

    @Test("Edits autosave atomically and external changes reload")
    @MainActor
    func autosaveAndReload() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesURL = root.appendingPathComponent("notes")
        let store = LibraryStore(notesDirectoryURL: notesURL, seedSampleData: false)
        store.addCard()
        store.updateSelectedCard(title: "Autosave", body: "First version")
        let fileURL = try #require(store.selectedCard?.fileURL)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "First version")

        try Data("Changed outside minute".utf8).write(to: fileURL, options: .atomic)
        store.reloadFromDisk()
        #expect(store.selectedCard?.body == "Changed outside minute")
    }

    @Test("Backlinks resolve by stable timestamp")
    @MainActor
    func backlinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MarkdownLibrary(directoryURL: root)
        var target = NoteCard(
            timestampID: "202609132132",
            title: "Target",
            body: "Target body",
            accent: .blue
        )
        target.fileURL = try library.save(target)
        var source = NoteCard(
            timestampID: "202609132133",
            title: "Source",
            body: "See @202609132132 Target.",
            accent: .pink
        )
        source.fileURL = try library.save(source)
        let store = LibraryStore(notesDirectoryURL: root, seedSampleData: false)
        let loadedTarget = try #require(store.cards.first { $0.timestampID == target.timestampID })

        #expect(store.backlinks(to: loadedTarget).map(\.timestampID) == [source.timestampID])
    }

    @Test("Large libraries load and duplicate timestamps stay unambiguous")
    func largeLibrary() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for index in 0..<300 {
            let identifier = String(format: "202601%06d", index)
            let url = root.appendingPathComponent("\(identifier) Note \(index).md")
            try Data("Body \(index)".utf8).write(to: url, options: .atomic)
        }

        let duplicateOld = root.appendingPathComponent("202609132134 Old.md")
        let duplicateNew = root.appendingPathComponent("202609132134 New.md")
        try Data("old".utf8).write(to: duplicateOld)
        try Data("new".utf8).write(to: duplicateNew)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: duplicateOld.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)],
            ofItemAtPath: duplicateNew.path
        )

        let cards = try MarkdownLibrary(directoryURL: root).load()
        #expect(cards.count == 301)
        #expect(cards.first { $0.timestampID == "202609132134" }?.title == "New")
    }

    @Test("Filenames are safe and parseable")
    func filenames() throws {
        #expect(MarkdownLibrary.sanitizeTitle("  A / risky:\n title. ") == "A risky title")
        let parsed = try #require(
            MarkdownLibrary.parseFilename("202609132135-2 A note")
        )
        #expect(parsed.identifier == "202609132135-2")
        #expect(parsed.title == "A note")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minute-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
