import Foundation
import Chromabase

struct ExportBatchCheckpoint: Codable, Equatable {
    static let currentVersion = 2

    enum LoadError: Error, Equatable {
        case fileNotFound
        case permissionDenied
        case readFailed
        case decodingFailed
        case validationFailed
    }

    struct PrinterOutputProfile: Codable, Equatable {
        let profileName: String
        let profileSHA256: String
        let iccProfileData: Data

        init(_ snapshot: ICCOutputProfileSnapshot) {
            profileName = snapshot.profileName
            profileSHA256 = snapshot.profileSHA256
            iccProfileData = snapshot.iccProfileData
        }

        var resolved: ICCOutputProfileSnapshot? {
            ICCOutputProfileSnapshot(
                profileName: profileName,
                iccProfileData: iccProfileData,
                expectedSHA256: profileSHA256
            )
        }
    }

    struct Item: Codable, Equatable {
        enum State: String, Codable {
            case queued
            case running
            case succeeded
            case failed
            case cancelled
        }

        let id: UUID
        let frameID: UUID
        let outputPath: String
        let format: String
        let writeSidecar: Bool
        let writeMainFlatMaster: Bool
        let writeOriginalRaw: Bool
        let colorSpace: String
        let dpi: Int
        let longEdge: Int?
        let jpegQuality: Double?
        let tiffCompression: String?
        let tiffBitDepth: Int?
        let preserveAlpha: Bool?
        let metadataPolicy: String?
        let outputSharpening: Double?
        let outputSharpeningMedium: String?
        let printerOutputProfileSHA256: String?
        let printComposition: PrintCompositionSettings?
        let recipePresetID: UUID?
        let recipePresetName: String?
        let recipeSHA256: String?
        let state: State
    }

    let version: Int
    let updatedAt: Date
    let printerOutputProfiles: [PrinterOutputProfile]?
    let items: [Item]

    @MainActor
    init(plans: [ExportBatchPlan], store: ExportBatchStore, date: Date = Date()) {
        version = Self.currentVersion
        updatedAt = date
        var profilesBySHA256: [String: PrinterOutputProfile] = [:]
        for profile in plans.compactMap(\.printerOutputProfile) {
            profilesBySHA256[profile.profileSHA256] = PrinterOutputProfile(profile)
        }
        printerOutputProfiles = profilesBySHA256.values.sorted {
            $0.profileSHA256 < $1.profileSHA256
        }
        items = plans.compactMap { plan in
            guard let state = store.state(for: plan.id) else { return nil }
            return Item(
                id: plan.id,
                frameID: plan.frame.id,
                outputPath: plan.outputURL.standardizedFileURL.path,
                format: plan.format.rawValue,
                writeSidecar: plan.writeSidecar,
                writeMainFlatMaster: plan.writeMainFlatMaster,
                writeOriginalRaw: plan.writeOriginalRaw,
                colorSpace: plan.options.colorSpace.rawValue,
                dpi: plan.options.dpi,
                longEdge: plan.options.longEdge,
                jpegQuality: plan.options.jpegQuality,
                tiffCompression: plan.options.tiffCompression.rawValue,
                tiffBitDepth: plan.options.tiffBitDepth.rawValue,
                preserveAlpha: plan.options.preserveAlpha,
                metadataPolicy: plan.options.metadataPolicy.rawValue,
                outputSharpening: plan.options.outputSharpening,
                outputSharpeningMedium: plan.options.outputSharpeningMedium.rawValue,
                printerOutputProfileSHA256: plan.printerOutputProfile?.profileSHA256,
                printComposition: plan.printComposition,
                recipePresetID: plan.recipeIdentity?.presetID,
                recipePresetName: plan.recipeIdentity?.presetName,
                recipeSHA256: plan.recipeIdentity?.configurationSHA256,
                state: Self.checkpointState(state)
            )
        }
    }

    static func url(for catalogURL: URL) -> URL {
        catalogURL.deletingLastPathComponent()
            .appendingPathComponent("ExportBatch", isDirectory: true)
            .appendingPathComponent("checkpoint.json")
    }

    static func load(from url: URL) -> ExportBatchCheckpoint? {
        try? read(from: url)
    }

    static func read(from url: URL) throws -> ExportBatchCheckpoint {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw loadError(for: error)
        }
        let value: Self
        do {
            value = try decoder.decode(Self.self, from: data)
        } catch {
            throw LoadError.decodingFailed
        }
        guard (1...currentVersion).contains(value.version),
              Set(value.items.map(\.id)).count == value.items.count,
              Set(value.items.map(\.frameID)).count == value.items.count,
              value.validPrinterOutputProfiles,
              value.items.allSatisfy({ item in
                validSHA256(item.recipeSHA256)
                    && validSHA256(item.printerOutputProfileSHA256)
                    && (item.printComposition?.isValid ?? true)
                    && (item.recipePresetID == nil || item.recipeSHA256 != nil)
                    && (item.recipePresetName?.utf8.count ?? 0) <= 80
              }) else {
            throw LoadError.validationFailed
        }
        return value
    }

    static func loadError(for error: Error) -> LoadError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileReadNoSuchFile:
                return .fileNotFound
            case .fileReadNoPermission:
                return .permissionDenied
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case 2:
                return .fileNotFound
            case 13:
                return .permissionDenied
            default:
                break
            }
        }
        return .readFailed
    }

    private var validPrinterOutputProfiles: Bool {
        let profiles = printerOutputProfiles ?? []
        let hashes = Set(profiles.map(\.profileSHA256))
        guard hashes.count == profiles.count,
              profiles.allSatisfy({ $0.resolved != nil }) else { return false }
        return items.allSatisfy { item in
            item.printerOutputProfileSHA256.map(hashes.contains) ?? true
        }
    }

    private static func validSHA256(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    private static func checkpointState(_ state: ExportBatchStore.State) -> Item.State {
        switch state {
        case .queued: .queued
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }
}
