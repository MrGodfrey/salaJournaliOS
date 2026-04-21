import Foundation

enum L10n {
    private final class BundleToken {}

    nonisolated private static let bundle = Bundle(for: BundleToken.self)

    nonisolated static var locale: Locale {
        if let languageOverride {
            return Locale(identifier: languageOverride)
        }

        if let preferredLocalization = bundle.preferredLocalizations.first {
            return Locale(identifier: preferredLocalization)
        }

        if let preferredLanguage = Locale.preferredLanguages.first {
            return Locale(identifier: preferredLanguage)
        }

        return .autoupdatingCurrent
    }

    nonisolated static func string(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    nonisolated static func blogTag(_ rawTag: String) -> String {
        switch rawTag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale) {
        case "reading":
            return string("Reading")
        case "watching":
            return string("Watching")
        case "game":
            return string("Game")
        case "trip":
            return string("Trip")
        case "note":
            return string("note")
        default:
            return rawTag
        }
    }

    nonisolated static func sharedRepositoryDisplayName(ownerName: String?) -> String {
        guard let ownerName = ownerName?.trimmed.nilIfEmpty else {
            return string("Shared Repository")
        }

        return format("%@'s Shared Repository", ownerName)
    }

    nonisolated static func localizedRepositoryDisplayName(_ storedName: String, descriptor: RepositoryDescriptor, source: RepositorySource) -> String {
        if source == .local {
            return string("My Repository")
        }

        if let ownerName = ownerName(fromPossessiveSharedName: storedName) {
            return sharedRepositoryDisplayName(ownerName: ownerName)
        }

        if storedName == "Shared Repository" {
            return string("Shared Repository")
        }

        let legacyOwnerPrefix = "Shared Repository · "
        if storedName.hasPrefix(legacyOwnerPrefix) {
            let ownerName = String(storedName.dropFirst(legacyOwnerPrefix.count)).trimmed
            return format("Shared Repository · %@", ownerName)
        }

        let defaultDisplayName = descriptor.defaultDisplayName
        if storedName == defaultDisplayName {
            return defaultDisplayName
        }

        return storedName
    }

    nonisolated private static var languageOverride: String? {
        guard let rawValue = getenv("THATDAY_APP_LANGUAGE") else {
            return nil
        }

        return String(cString: rawValue).trimmed.nilIfEmpty
    }

    nonisolated private static var localizedBundle: Bundle {
        guard let languageOverride,
              let bundlePath = bundle.path(forResource: languageOverride, ofType: "lproj"),
              let localizedBundle = Bundle(path: bundlePath) else {
            return bundle
        }

        return localizedBundle
    }

    nonisolated private static func ownerName(fromPossessiveSharedName name: String) -> String? {
        let suffix = "'s Shared Repository"
        guard name.hasSuffix(suffix) else {
            return nil
        }

        return String(name.dropLast(suffix.count)).trimmed.nilIfEmpty
    }
}
