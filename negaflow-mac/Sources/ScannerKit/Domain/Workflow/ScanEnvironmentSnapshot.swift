import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

public struct ScanEnvironmentSnapshot: Codable, Sendable, Equatable {
    public let applicationName: String
    public let applicationVersion: String
    public let operatingSystem: String
    public let operatingSystemVersion: String
    public let architecture: String?

    public init(
        applicationName: String,
        applicationVersion: String,
        operatingSystem: String,
        operatingSystemVersion: String,
        architecture: String? = nil
    ) {
        self.applicationName = applicationName
        self.applicationVersion = applicationVersion
        self.operatingSystem = operatingSystem
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
    }

    private enum CodingKeys: String, CodingKey {
        case applicationName
        case applicationVersion
        case operatingSystem
        case operatingSystemVersion
        case architecture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        applicationVersion = try container.decode(String.self, forKey: .applicationVersion)
        operatingSystem = try container.decode(String.self, forKey: .operatingSystem)
        operatingSystemVersion = try container.decode(String.self, forKey: .operatingSystemVersion)
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture)
        try decodeValidated(self, decoder: decoder)
    }

    func validate() throws {
        try requireNonempty(applicationName, field: "environment.applicationName")
        try requireNonempty(applicationVersion, field: "environment.applicationVersion")
        try requireNonempty(operatingSystem, field: "environment.operatingSystem")
        try requireNonempty(operatingSystemVersion, field: "environment.operatingSystemVersion")
        try requireOptionalNonempty(architecture, field: "environment.architecture")
    }
}

/// full 캡처가 fixity 완료 뒤 어떤 비파괴 프레임으로 publish되어야 하는지 세션 시작 시
/// 고정한다. 캡처 중 crash가 나도 UUID/번호/초기 현상 상태를 추측하지 않고 재구성한다.
