import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

extension Substring {
    static func + (lhs: Substring, rhs: String) -> String {
        String(lhs) + rhs
    }
}

extension Calendar {
    func isSameMonthDay(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsComponents = dateComponents([.month, .day], from: lhs)
        let rhsComponents = dateComponents([.month, .day], from: rhs)
        return lhsComponents.month == rhsComponents.month && lhsComponents.day == rhsComponents.day
    }

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    func dayIdentifier(for date: Date) -> String {
        let components = dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
