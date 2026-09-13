import Foundation

enum TimestampID {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()

    static func make(at date: Date = .now, excluding existing: Set<String>) -> String {
        let prefix = formatter.string(from: date)
        guard existing.contains(prefix) else { return prefix }

        var sequence = 2
        while existing.contains("\(prefix)-\(sequence)") {
            sequence += 1
        }
        return "\(prefix)-\(sequence)"
    }
}
