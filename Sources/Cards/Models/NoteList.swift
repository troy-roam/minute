import Foundation

struct NoteList: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var symbol: String
    var cards: [NoteCard]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        symbol: String = "rectangle.stack.fill",
        cards: [NoteCard] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.cards = cards
        self.createdAt = createdAt
    }
}
