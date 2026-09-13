import Foundation

enum MarkdownRenderer {
    private static let cardLinkPattern = #"(?<![A-Za-z0-9])@(\d{12}(?:-\d+)?)"#

    static func attributedString(from source: String) -> AttributedString {
        let range = NSRange(source.startIndex..., in: source)
        let regex = try? NSRegularExpression(pattern: cardLinkPattern)
        let linkedMarkdown = regex?.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "[@$1](card://$1)"
        ) ?? source

        return (try? AttributedString(
            markdown: linkedMarkdown,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(source)
    }

    static func cardIdentifier(from url: URL) -> String? {
        guard url.scheme == "card" else { return nil }
        return url.host ?? url.pathComponents.dropFirst().first
    }
}
