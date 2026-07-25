import Foundation
import CoreGraphics
import ImageIO
import Chromabase

extension ExternalScannerBackend {
    public func cancelScan() async {
        await cancelCurrentProcessAndWait()
    }

    func validatePluginCompatibility() throws {
        guard plugin.manifest.isSupportedByHost else {
            throw failure(.ioFailure, "지원하지 않는 scanner plugin manifest 또는 protocol 버전")
        }
        if let expectedIdentity = plugin.trustIdentity {
            guard ScannerPluginHost.currentTrustIdentity(for: plugin) == expectedIdentity else {
                throw failure(.ioFailure, "scanner plugin 파일이 발견 이후 변경되어 실행을 차단함")
            }
        }
    }

    func failure(_ code: ScannerError.Code, _ message: String) -> ScannerError {
        let err = ScannerError(code, message)
        lastError = err
        return err
    }
}
