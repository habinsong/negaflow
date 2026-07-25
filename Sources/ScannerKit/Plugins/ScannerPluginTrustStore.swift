import Foundation

public enum ScannerPluginApprovalState: Sendable, Equatable {
    case approved
    case approvalRequired
    case identityChanged
    case invalidIdentity
    case storeUnavailable
}

public enum ScannerPluginTrustStoreError: Error, Sendable, Equatable {
    case unavailable
    case invalidStore
    case invalidPluginIdentity
    case writeFailed
}

public struct ScannerPluginTrustRecord: Codable, Sendable, Equatable {
    public let identity: ScannerPluginTrustIdentity
    public let approvedAt: Date

    public init(identity: ScannerPluginTrustIdentity, approvedAt: Date) {
        self.identity = identity
        self.approvedAt = approvedAt
    }
}

public struct ScannerPluginTrustStore: Sendable {
    private struct Envelope: Codable, Equatable {
        static let currentVersion = 1
        var version: Int
        var records: [ScannerPluginTrustRecord]
    }

    private static let maximumStoreBytes = 1 * 1_024 * 1_024
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var `default`: ScannerPluginTrustStore? {
        guard let installDirectory = ScannerPluginHost.defaultInstallDirectory else {
            return nil
        }
        return ScannerPluginTrustStore(
            fileURL: installDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("scanner-plugin-trust.json")
        )
    }

    public func approvalState(
        for plugin: InstalledScannerPlugin
    ) -> ScannerPluginApprovalState {
        guard let expectedIdentity = plugin.trustIdentity,
              ScannerPluginHost.currentTrustIdentity(for: plugin) == expectedIdentity else {
            return .invalidIdentity
        }
        let envelope: Envelope
        do {
            envelope = try loadEnvelope()
        } catch {
            return .storeUnavailable
        }
        guard let record = envelope.records.first(where: {
            $0.identity.pluginID == expectedIdentity.pluginID
        }) else {
            return .approvalRequired
        }
        return record.identity == expectedIdentity ? .approved : .identityChanged
    }

    public func approvedPlugins(
        from plugins: [InstalledScannerPlugin]
    ) -> [InstalledScannerPlugin] {
        plugins.filter { approvalState(for: $0) == .approved }
    }

    public func records() throws -> [ScannerPluginTrustRecord] {
        try loadEnvelope().records
    }

    public func approve(
        _ plugin: InstalledScannerPlugin,
        approvedAt: Date = Date()
    ) throws {
        guard let identity = plugin.trustIdentity,
              ScannerPluginHost.currentTrustIdentity(for: plugin) == identity else {
            throw ScannerPluginTrustStoreError.invalidPluginIdentity
        }
        var envelope = try loadEnvelope()
        envelope.records.removeAll { $0.identity.pluginID == identity.pluginID }
        let normalizedApprovalDate = Date(
            timeIntervalSince1970: approvedAt.timeIntervalSince1970.rounded(.down)
        )
        envelope.records.append(ScannerPluginTrustRecord(
            identity: identity,
            approvedAt: normalizedApprovalDate
        ))
        envelope.records.sort { $0.identity.pluginID < $1.identity.pluginID }
        try writeAndVerify(envelope)
    }

    public func revoke(pluginID: String) throws {
        var envelope = try loadEnvelope()
        let previousCount = envelope.records.count
        envelope.records.removeAll { $0.identity.pluginID == pluginID }
        guard envelope.records.count != previousCount else { return }
        try writeAndVerify(envelope)
    }

    private func loadEnvelope() throws -> Envelope {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Envelope(version: Envelope.currentVersion, records: [])
        }
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ), values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= Self.maximumStoreBytes,
              let data = try? Data(contentsOf: fileURL),
              data.count <= Self.maximumStoreBytes,
              let envelope = try? JSONDecoder.iso8601.decode(Envelope.self, from: data),
              envelope.version == Envelope.currentVersion,
              valid(envelope) else {
            throw ScannerPluginTrustStoreError.invalidStore
        }
        return envelope
    }

    private func valid(_ envelope: Envelope) -> Bool {
        let pluginIDs = envelope.records.map { $0.identity.pluginID }
        guard Set(pluginIDs).count == pluginIDs.count else { return false }
        return envelope.records.allSatisfy { record in
            ScannerPluginManifest.isValidPluginID(record.identity.pluginID)
                && validSHA256(record.identity.manifestSHA256)
                && validSHA256(record.identity.executableSHA256)
        }
    }

    private func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
        }
    }

    private func writeAndVerify(_ envelope: Envelope) throws {
        guard valid(envelope) else {
            throw ScannerPluginTrustStoreError.invalidStore
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope),
              data.count <= Self.maximumStoreBytes else {
            throw ScannerPluginTrustStoreError.writeFailed
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path),
           let values = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw ScannerPluginTrustStoreError.writeFailed
        }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            let readback = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder.iso8601.decode(Envelope.self, from: readback)
            guard readback == data, decoded == envelope else {
                throw ScannerPluginTrustStoreError.writeFailed
            }
        } catch let error as ScannerPluginTrustStoreError {
            throw error
        } catch {
            throw ScannerPluginTrustStoreError.writeFailed
        }
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
