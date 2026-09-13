import Foundation

struct MarkdownLibrary {
    let directoryURL: URL
    private let fileManager: FileManager
    private let trashDirectoryURL: URL?

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        trashDirectoryURL: URL? = nil
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.trashDirectoryURL = trashDirectoryURL
    }

    func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func load() throws -> [NoteCard] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        var newestByIdentifier: [String: NoteCard] = [:]

        for url in urls where url.pathExtension.lowercased() == "md" {
            guard let parsed = Self.parseFilename(url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url),
                  let markdown = String(data: data, encoding: .utf8) else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            let modified = values?.contentModificationDate ?? .distantPast
            let created = values?.creationDate ?? modified
            let card = NoteCard(
                timestampID: parsed.identifier,
                title: parsed.title,
                body: markdown,
                accent: Self.accent(for: parsed.identifier),
                createdAt: created,
                updatedAt: modified,
                fileURL: url
            )
            if let existing = newestByIdentifier[parsed.identifier],
               existing.updatedAt >= modified {
                continue
            }
            newestByIdentifier[parsed.identifier] = card
        }

        return newestByIdentifier.values.sorted { $0.timestampID < $1.timestampID }
    }

    func save(_ card: NoteCard, replacing previousURL: URL? = nil) throws -> URL {
        try createDirectoryIfNeeded()
        let destination = fileURL(for: card)

        if let previousURL,
           previousURL.standardizedFileURL != destination.standardizedFileURL,
           fileManager.fileExists(atPath: previousURL.path) {
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.moveItem(at: previousURL, to: destination)
        }

        try Data(card.body.utf8).write(to: destination, options: .atomic)
        return destination
    }

    func moveToTrash(_ card: NoteCard) throws -> URL {
        guard let fileURL = card.fileURL else { throw CocoaError(.fileNoSuchFile) }
        if let trashDirectoryURL {
            try fileManager.createDirectory(at: trashDirectoryURL, withIntermediateDirectories: true)
            let destination = trashDirectoryURL.appendingPathComponent(
                "\(UUID().uuidString)-\(fileURL.lastPathComponent)"
            )
            try fileManager.moveItem(at: fileURL, to: destination)
            return destination
        }
        var resultingURL: NSURL?
        try fileManager.trashItem(at: fileURL, resultingItemURL: &resultingURL)
        guard let resultingURL else { throw CocoaError(.fileNoSuchFile) }
        return resultingURL as URL
    }

    func restoreFromTrash(_ trashURL: URL, to originalURL: URL) throws {
        try createDirectoryIfNeeded()
        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.moveItem(at: trashURL, to: originalURL)
    }

    func fileURL(for card: NoteCard) -> URL {
        let cleanTitle = Self.sanitizeTitle(card.title)
        let filename = cleanTitle.isEmpty
            ? card.timestampID
            : "\(card.timestampID) \(cleanTitle)"
        return directoryURL.appendingPathComponent(filename).appendingPathExtension("md")
    }

    static func parseFilename(_ filename: String) -> (identifier: String, title: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\d{12}(?:-\d+)?)(?:\s+(.*))?$"#
        ) else { return nil }
        let value = filename as NSString
        guard let match = regex.firstMatch(
            in: filename,
            range: NSRange(location: 0, length: value.length)
        ) else { return nil }
        let identifier = value.substring(with: match.range(at: 1))
        let titleRange = match.range(at: 2)
        let title = titleRange.location == NSNotFound ? "" : value.substring(with: titleRange)
        return (identifier, title)
    }

    static func sanitizeTitle(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\n\r\t").union(.controlCharacters)
        return title.components(separatedBy: invalid)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private static func accent(for identifier: String) -> CardAccent {
        let value = identifier.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return CardAccent.allCases[value % CardAccent.allCases.count]
    }
}
