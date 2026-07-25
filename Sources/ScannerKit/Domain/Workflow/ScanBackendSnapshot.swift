import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Session provenance snapshots

/// 세션이 시작될 때 선택된 백엔드/플러그인 정보를 값으로 고정한다.
public struct ScanBackendSnapshot: Codable, Sendable, Equatable {
    public let type: BackendType
    public let identifier: String
    public let version: String?
    public let pluginIdentifier: String?
    public let pluginVersion: String?

    public init(
        type: BackendType,
        identifier: String,
        version: String? = nil,
        pluginIdentifier: String? = nil,
        pluginVersion: String? = nil
    ) {
        self.type = type
        self.identifier = identifier
        self.version = version
        self.pluginIdentifier = pluginIdentifier
        self.pluginVersion = pluginVersion
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case identifier
        case version
        case pluginIdentifier
        case pluginVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(BackendType.self, forKey: .type)
        identifier = try container.decode(String.self, forKey: .identifier)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        pluginIdentifier = try container.decodeIfPresent(String.self, forKey: .pluginIdentifier)
        pluginVersion = try container.decodeIfPresent(String.self, forKey: .pluginVersion)
        try decodeValidated(self, decoder: decoder)
    }

    func validate() throws {
        try requireNonempty(identifier, field: "backend.identifier")
        try requireOptionalNonempty(version, field: "backend.version")
        try requireOptionalNonempty(pluginIdentifier, field: "backend.pluginIdentifier")
        try requireOptionalNonempty(pluginVersion, field: "backend.pluginVersion")
        if type == .plugin {
            guard let pluginIdentifier,
                  ScannerPluginManifest.isValidPluginID(pluginIdentifier) else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "plugin 백엔드는 안전한 pluginIdentifier 스냅샷이 필요합니다"
                )
            }
        } else if pluginIdentifier != nil || pluginVersion != nil {
            throw ScanWorkflowValidationError.invariantViolation(
                "plugin이 아닌 백엔드는 plugin provenance를 가질 수 없습니다"
            )
        }
    }
}

/// PREMIS creatingApplication/environment에 대응하는 캡처 생성 환경 스냅샷.
