import Foundation
import CoreGraphics
import ImageIO
import Chromabase

/// scan 이벤트(result/error)를 백그라운드 스트리밍 콜백에서 안전하게 수집한다.
final class ScanEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private let protocolVersion: Int
    private let requestID: UUID?
    private var _result: PluginScanEvent?
    private var _error: String?
    private var _protocolError: String?
    private var lastSequence: UInt64?
    private var terminalEventType: String?

    init(protocolVersion: Int, requestID: UUID?) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
    }

    func consume(line: String) -> ScanEventAction {
        lock.lock()
        defer { lock.unlock() }
        guard _protocolError == nil else { return .none }

        let isV2 = protocolVersion == ScannerPluginManifest.streamProtocolVersion
        let event: PluginScanEvent
        guard let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PluginScanEvent.self, from: data) else {
            if isV2 {
                _protocolError = terminalEventType.map {
                    "plugin protocol v2 \($0) 이후 이벤트"
                } ?? "plugin protocol v2 이벤트 파싱 실패"
            }
            return .none
        }
        event = decoded

        if isV2, let terminalEventType {
            _protocolError = event.type == terminalEventType
                ? "plugin scan \(terminalEventType) 중복"
                : "plugin protocol v2 \(terminalEventType) 이후 이벤트"
            return .none
        }

        if isV2 {
            guard event.protocolVersion == protocolVersion else {
                _protocolError = "plugin protocol v2 이벤트 버전 불일치"
                return .none
            }
            guard let requestID, event.requestID == requestID else {
                _protocolError = "plugin protocol v2 requestID 불일치"
                return .none
            }
            guard let sequence = event.sequence else {
                _protocolError = "plugin protocol v2 sequence 누락"
                return .none
            }
            if let lastSequence, sequence <= lastSequence {
                _protocolError = "plugin protocol v2 sequence가 엄격히 증가하지 않음"
                return .none
            }
            lastSequence = sequence
        }

        switch event.type {
        case "progress":
            let phase = event.phase.flatMap { ScanPhase(rawValue: $0) } ?? .scanningRGB
            return .progress(ScanProgress(
                phase: phase,
                fraction: event.fraction,
                message: event.message ?? ""
            ))
        case "result":
            guard _result == nil else {
                _protocolError = "plugin scan result 중복"
                return .none
            }
            _result = event
            if isV2 { terminalEventType = "result" }
            return .none
        case "error":
            let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _error = message.isEmpty ? "plugin scan error 이벤트" : message
            if isV2 { terminalEventType = "error" }
            return .none
        default:
            if isV2 {
                _protocolError = "plugin protocol v2 알 수 없는 이벤트 유형: \(event.type)"
            }
            return .none
        }
    }

    var result: PluginScanEvent? { lock.lock(); defer { lock.unlock() }; return _result }
    var error: String? { lock.lock(); defer { lock.unlock() }; return _error }
    var protocolError: String? { lock.lock(); defer { lock.unlock() }; return _protocolError }
}

enum ScanEventAction {
    case none
    case progress(ScanProgress)
}
