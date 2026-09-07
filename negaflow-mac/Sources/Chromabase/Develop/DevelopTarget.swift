import Foundation

public enum DevelopTarget: String, Codable, Sendable, CaseIterable {
    case main
    case print
    case noritsu
    case sp3000 = "sp-3000"
    case f135
    case hr
    case rescue
    case emulsion
    case reversal
    case dyeTransfer = "dye-transfer"
    case skipBleach = "skip-bleach"
    case plateGlass = "plate-glass"
    case amberGlass = "amber-glass"
    case ultramarine
    case terracotta
    case celadon
    case nacre
    case dichroic
    case wetzlar
    case classic
    case studio
    case rochester
    case slideShow = "slide-show"
    case cinema
    case pointAndShoot = "point-and-shoot"

    public var displayName: String {
        switch self {
        case .main: return "MAIN"
        case .print: return "PRINT"
        case .noritsu: return "HS"
        case .sp3000: return "SP"
        case .f135: return "F135"
        case .hr: return "HR"
        case .rescue: return "EXPIRED"
        case .emulsion: return "Emulsion"
        case .reversal: return "Reversal"
        case .dyeTransfer: return "Dye Transfer"
        case .skipBleach: return "Skip Bleach"
        case .plateGlass: return "Plate Glass"
        case .amberGlass: return "Amber Glass"
        case .ultramarine: return "Ultramarine"
        case .terracotta: return "Terracotta"
        case .celadon: return "Celadon"
        case .nacre: return "Nacre"
        case .dichroic: return "Dichroic"
        case .wetzlar: return "Wetzlar"
        case .classic: return "Classic"
        case .studio: return "Studio"
        case .rochester: return "Rochester"
        case .slideShow: return "Slide Show"
        case .cinema: return "Cinema"
        case .pointAndShoot: return "Point & Shoot"
        }
    }

    public var isScannerEmulation: Bool {
        switch self {
        case .noritsu, .sp3000, .f135, .hr: return true
        default: return false
        }
    }

    public var isCustom: Bool { Self.customTargets.contains(self) }

    public static let standardTargets: [DevelopTarget] = [
        .main, .print, .noritsu, .sp3000, .f135, .hr, .rescue,
    ]

    public static let customGroups: [[DevelopTarget]] = [
        [.emulsion, .reversal, .dyeTransfer, .skipBleach, .plateGlass, .amberGlass, .ultramarine, .terracotta, .celadon, .nacre, .dichroic],
        [.wetzlar, .classic, .studio, .rochester],
        [.slideShow, .cinema, .pointAndShoot],
    ]

    public static let customTargets = customGroups.flatMap { $0 }
}
