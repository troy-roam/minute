import Foundation

struct NoteCard: Identifiable, Codable, Hashable {
    let id: UUID
    var timestampID: String
    var title: String
    var body: String
    var richTextRTF: Data?
    var accent: CardAccent
    let createdAt: Date
    var updatedAt: Date
    var fileURL: URL?

    var name: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? timestampID : "\(timestampID) \(cleanTitle)"
    }

    init(
        id: UUID = UUID(),
        timestampID: String,
        title: String,
        body: String = "",
        richTextRTF: Data? = nil,
        accent: CardAccent,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.timestampID = timestampID
        self.title = title
        self.body = body
        self.richTextRTF = richTextRTF
        self.accent = accent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileURL = fileURL
    }
}

enum CardAccent: String, Codable, CaseIterable, Hashable {
    case blue
    case indigo
    case mint
    case orange
    case pink
    case plum
}
