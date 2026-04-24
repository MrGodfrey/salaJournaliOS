import Foundation
import NaturalLanguage
import CoreGraphics

enum HorizontalSwipeDirection: Equatable {
    case left
    case right

    nonisolated var pageOffset: Int {
        switch self {
        case .left:
            return 1
        case .right:
            return -1
        }
    }

    nonisolated static func direction(
        for translation: CGSize,
        minimumDistance: CGFloat = 48,
        dominanceRatio: CGFloat = 1.25
    ) -> HorizontalSwipeDirection? {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)

        guard horizontalDistance >= minimumDistance,
              horizontalDistance > verticalDistance * dominanceRatio else {
            return nil
        }

        return translation.width < 0 ? .left : .right
    }
}

extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    nonisolated var writtenWordCount: Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = self
        let ignoredScalars = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)

        var count = 0
        tokenizer.enumerateTokens(in: startIndex..<endIndex) { _, _ in
            count += 1
            return true
        }

        if count > 0 {
            return count
        }

        return unicodeScalars.reduce(into: 0) { count, scalar in
            if !ignoredScalars.contains(scalar) {
                count += 1
            }
        }
    }
}

extension Substring {
    nonisolated static func + (lhs: Substring, rhs: String) -> String {
        String(lhs) + rhs
    }
}

extension Calendar {
    nonisolated func isSameMonthDay(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsComponents = dateComponents([.month, .day], from: lhs)
        let rhsComponents = dateComponents([.month, .day], from: rhs)
        return lhsComponents.month == rhsComponents.month && lhsComponents.day == rhsComponents.day
    }

    nonisolated func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    nonisolated func dayIdentifier(for date: Date) -> String {
        let components = dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
