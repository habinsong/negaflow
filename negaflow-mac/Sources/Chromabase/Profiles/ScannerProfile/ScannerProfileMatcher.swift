import Foundation

public enum ScannerProfileMatcher {
    public static func matchingProfiles(
        target: DevelopTarget,
        filmType: FilmType,
        profiles: [ScannerProfile]
    ) -> [ScannerProfile] {
        guard let kind = profileKind(for: filmType) else { return [] }
        let scannerOrder = scannerNames(for: target)
        return profiles
            .filter { profile in
                scannerOrder.contains(profile.scanner) && profile.kind == kind
            }
            .sorted { lhs, rhs in
                let lhsScanner = scannerOrder.firstIndex(of: lhs.scanner) ?? Int.max
                let rhsScanner = scannerOrder.firstIndex(of: rhs.scanner) ?? Int.max
                if lhsScanner != rhsScanner { return lhsScanner < rhsScanner }
                return lhs.filmKey.localizedStandardCompare(rhs.filmKey) == .orderedAscending
            }
    }

    public static func preferredProfileID(
        target: DevelopTarget,
        filmType: FilmType,
        filmStockDminID: String?,
        currentID: String?,
        profiles: [ScannerProfile]
    ) -> String? {
        let matches = matchingProfiles(target: target, filmType: filmType, profiles: profiles)
            .filter { $0.validationStatus.allowsAutomaticUse }
        guard !matches.isEmpty else { return nil }

        if let filmStockDminID {
            let candidates = Set(filmKeyCandidates(for: filmStockDminID))
            if let exact = matches.first(where: { candidates.contains(normalizedFilmKey($0.filmKey)) }) {
                return exact.id
            }
        }

        if let currentID, matches.contains(where: { $0.id == currentID }) {
            return currentID
        }

        return matches.first?.id
    }

    public static func filmKeyCandidates(for filmStockDminID: String) -> [String] {
        var candidates = [normalizedFilmKey(filmStockDminID)]
        if filmStockDminID.hasPrefix("vision3-") {
            candidates.append(normalizedFilmKey("kodak-\(filmStockDminID)"))
        }
        return candidates
    }

    private static func scannerNames(for target: DevelopTarget) -> [String] {
        switch target {
        case .main, .print, .rescue, .f135, .hr:
            return []
        case .noritsu:
            return ["NORITSU"]
        case .sp3000:
            return ["SP-3000"]
        }
    }

    private static func profileKind(for filmType: FilmType) -> String? {
        switch filmType {
        case .colorNegative:
            return "color nega"
        case .colorPositive:
            return "color slide"
        case .bwNegative, .bwPositive:
            return nil
        }
    }

    private static func normalizedFilmKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}
