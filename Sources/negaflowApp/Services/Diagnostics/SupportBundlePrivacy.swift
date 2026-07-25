import CryptoKit
import Foundation
import ScannerKit

struct SupportBundlePrivacyHasher: Sendable {
    private let salt: Data

    init(salt: Data = Data(UUID().uuidString.utf8)) {
        self.salt = salt
    }

    func hash(_ value: String) -> String {
        var payload = salt
        payload.append(contentsOf: value.utf8)
        return SHA256.hash(data: payload)
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension ScannerPluginApprovalState {
    var supportBundleCode: String {
        switch self {
        case .approved: "approved"
        case .approvalRequired: "approvalRequired"
        case .identityChanged: "identityChanged"
        case .invalidIdentity: "invalidIdentity"
        case .storeUnavailable: "storeUnavailable"
        }
    }
}
