import Foundation
import OSLog

enum AppDiagnostics {
    static let subsystem = "com.songhabin.negaflow"
    private static let eventStore = AppDiagnosticEventStore()

    static func start(
        _ operation: AppDiagnosticOperation,
        category: AppDiagnosticCategory
    ) -> AppOperationTrace {
        AppOperationTrace(category: category, operation: operation)
    }

    static var recentEvents: [AppDiagnosticEvent] {
        eventStore.snapshot()
    }

    static func errorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return sanitizedCode("\(String(reflecting: type(of: error)))#\(nsError.code)")
    }

    static func sanitizedCode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._#-"))
        let scalars = value.unicodeScalars.prefix(120).map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        return String(scalars)
    }

    static func publish(_ event: AppDiagnosticEvent, logger: Logger) {
        eventStore.append(event)
        let operation = event.operation.rawValue
        let operationID = event.operationID.uuidString
        let code = event.code ?? "none"
        switch event.severity {
        case .debug:
            logger.debug("\(operation, privacy: .public) \(operationID, privacy: .public) \(code, privacy: .public)")
        case .info:
            logger.info("\(operation, privacy: .public) \(operationID, privacy: .public) \(code, privacy: .public)")
        case .notice:
            logger.notice("\(operation, privacy: .public) \(operationID, privacy: .public) \(code, privacy: .public)")
        case .error:
            logger.error("\(operation, privacy: .public) \(operationID, privacy: .public) \(code, privacy: .public)")
        case .fault:
            logger.fault("\(operation, privacy: .public) \(operationID, privacy: .public) \(code, privacy: .public)")
        }
    }

    static func clearForTesting() {
        eventStore.removeAll()
    }
}

final class AppOperationTrace: @unchecked Sendable {
    let operationID: UUID
    let category: AppDiagnosticCategory
    let operation: AppDiagnosticOperation

    private let logger: Logger
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID
    private let intervalState: OSSignpostIntervalState
    private let lock = NSLock()
    private var completed = false

    init(category: AppDiagnosticCategory, operation: AppDiagnosticOperation) {
        let logger = Logger(
            subsystem: AppDiagnostics.subsystem,
            category: category.rawValue
        )
        let signposter = OSSignposter(logger: logger)
        let signpostID = signposter.makeSignpostID()
        self.operationID = UUID()
        self.category = category
        self.operation = operation
        self.logger = logger
        self.signposter = signposter
        self.signpostID = signpostID
        self.intervalState = signposter.beginInterval(
            operation.signpostName,
            id: signpostID
        )
        publish(phase: .begin, severity: .notice, code: nil)
    }

    func recordError(_ error: Error) {
        recordError(code: AppDiagnostics.errorCode(error))
    }

    func recordError(code: String) {
        let safeCode = AppDiagnostics.sanitizedCode(code)
        signposter.emitEvent("Operation Error", id: signpostID)
        publish(phase: .error, severity: .error, code: safeCode)
    }

    func finish() {
        complete(phase: .end, severity: .info, code: nil)
    }

    func fail(_ error: Error) {
        fail(code: AppDiagnostics.errorCode(error))
    }

    func fail(code: String) {
        complete(
            phase: .error,
            severity: .error,
            code: AppDiagnostics.sanitizedCode(code)
        )
    }

    deinit {
        finish()
    }

    private func complete(
        phase: AppDiagnosticPhase,
        severity: AppDiagnosticSeverity,
        code: String?
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        if phase == .error {
            signposter.emitEvent("Operation Error", id: signpostID)
        }
        publish(phase: phase, severity: severity, code: code)
        signposter.endInterval(operation.signpostName, intervalState)
    }

    private func publish(
        phase: AppDiagnosticPhase,
        severity: AppDiagnosticSeverity,
        code: String?
    ) {
        AppDiagnostics.publish(
            AppDiagnosticEvent(
                timestamp: Date(),
                operationID: operationID,
                category: category,
                operation: operation,
                phase: phase,
                severity: severity,
                code: code
            ),
            logger: logger
        )
    }
}
