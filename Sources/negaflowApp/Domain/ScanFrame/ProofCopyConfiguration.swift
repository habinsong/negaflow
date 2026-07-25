import Chromabase
import CryptoKit
import Foundation

struct ProofCopyConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let profileName: String
    let profileSHA256: String
    let colorSpace: ExportColorSpace
    let simulation: SoftProofSimulation
    let usesCustomProfile: Bool
    let embeddedICCProfileData: Data?

    init?(
        settings: SoftProofSettings,
        profileName: String
    ) {
        guard settings.isEnabled else { return nil }
        let profileData: Data
        if let custom = settings.iccProfileData {
            guard SoftProof.rgbOutputColorSpace(fromICCData: custom) != nil else { return nil }
            profileData = custom
            usesCustomProfile = true
            embeddedICCProfileData = custom
        } else {
            guard let builtIn = SoftProof.profile(for: settings.colorSpace)?.iccData else { return nil }
            profileData = builtIn
            usesCustomProfile = false
            embeddedICCProfileData = nil
        }
        schemaVersion = Self.currentSchemaVersion
        self.profileName = profileName
        profileSHA256 = Self.sha256(profileData)
        colorSpace = settings.colorSpace
        simulation = settings.simulation
    }

    var resolvedSoftProofSettings: SoftProofSettings? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        if usesCustomProfile {
            guard let data = embeddedICCProfileData,
                  Self.sha256(data) == profileSHA256,
                  SoftProof.rgbOutputColorSpace(fromICCData: data) != nil else { return nil }
            return SoftProofSettings(
                isEnabled: true,
                colorSpace: colorSpace,
                simulation: simulation,
                iccProfileData: data
            )
        }
        guard embeddedICCProfileData == nil,
              let profile = SoftProof.profile(for: colorSpace),
              Self.sha256(profile.iccData) == profileSHA256 else { return nil }
        return SoftProofSettings(
            isEnabled: true,
            colorSpace: colorSpace,
            simulation: simulation
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
