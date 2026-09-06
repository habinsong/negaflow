import Foundation
import OSLog

enum InputGammaPreviewTrace {
    private static let enabled = ProcessInfo.processInfo.environment["NEGAFLOW_GAMMA_PREVIEW_TRACE"] == "1"
    private static let logger = Logger(subsystem: AppDiagnostics.subsystem, category: "gamma-preview")

    static func emit(_ phase: String, frameID: UUID, session: UInt64, value: Double?) {
        guard enabled else { return }
        let number = value.map { String(format: "%.1f", $0) } ?? "auto"
        AppDiagnostics.publish(AppDiagnosticEvent(timestamp: Date(), operationID: frameID,
            category: .develop, operation: .developFrame, phase: .event, severity: .notice,
            code: "gamma_\(phase)_\(session)_\(number)"), logger: logger)
    }
}
