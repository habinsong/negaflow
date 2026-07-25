import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func cancelScan() async {
        await cancelActiveScanWorkflow()
    }

    /// 우측 상단 "진단" 리포트를 구조화 데이터로 구성한다. 스캐너 정보에 더해 실제 문제를
    /// 진단할 수 있게 최근 오류(사람이 읽는 메시지), 최근 실패 이벤트(machine code),
    /// 라이브러리 상태를 종류별 섹션으로 담는다. 팝오버(DiagnosticsReportView)가 렌더한다.
    func runDiagnostics() async {
        diagnosticsCenter.isGenerating = true

        var report = DiagnosticsReport()
        report.problems = errorLog.entries.suffix(12).reversed().map {
            DiagnosticsReport.Problem(message: $0.message, date: $0.date)
        }
        report.failureEvents = AppDiagnostics.recentEvents
            .filter { $0.phase == .error }
            .suffix(12)
            .reversed()
            .map {
                DiagnosticsReport.FailureEvent(
                    title: $0.operation.rawValue,
                    code: $0.code ?? "error",
                    date: $0.timestamp
                )
            }

        let yes = text(AppLocalizedText.diagnosticsValueYes)
        let no = text(AppLocalizedText.diagnosticsValueNo)
        report.libraryStats = [
            DiagnosticsReport.Stat(
                label: text(AppLocalizedText.diagnosticsStatFrames),
                value: "\(frames.count)"
            ),
            DiagnosticsReport.Stat(
                label: text(AppLocalizedText.diagnosticsStatUnsaved),
                value: hasUnsavedLibraryChanges ? yes : no,
                isWarning: hasUnsavedLibraryChanges
            ),
            DiagnosticsReport.Stat(
                label: text(AppLocalizedText.diagnosticsStatLifecycle),
                value: "\(libraryLifecycleState)"
            ),
        ]
        if let persistence = libraryCatalogPersistenceError {
            report.libraryStats.append(DiagnosticsReport.Stat(
                label: text(AppLocalizedText.diagnosticsStatSaveError),
                value: "generation \(persistence.generation)",
                isWarning: true
            ))
        }

        await populateScannerStats(into: &report)

        report.generatedAt = Date()
        diagnosticsCenter.report = report
        diagnosticsCenter.isGenerating = false
    }

    private func populateScannerStats(into report: inout DiagnosticsReport) async {
        guard let id = effectiveScannerID, let backend else {
            report.scannerAvailable = false
            return
        }
        report.scannerAvailable = true
        do {
            let capabilities = try await backend.getCapabilities(scannerID: id)
            let pluginList = installedScannerPlugins.isEmpty
                ? text(AppLocalizedPhrase.noInstalledPlugins)
                : installedScannerPlugins.map { "\($0.name) [\($0.id)]" }.joined(separator: ", ")
            let yes = text(AppLocalizedText.diagnosticsValueYes)
            let no = text(AppLocalizedText.diagnosticsValueNo)
            report.scannerStats = [
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedPhrase.scannerLabel),
                    value: activeScannerDisplayName
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedText.diagnosticsScannerBackend),
                    value: backend.backendType.rawValue
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedText.diagnosticsScannerPlugins),
                    value: pluginList
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedPhrase.resolution),
                    value: capabilities.supportedResolutions.map { "\($0.dpi)" }.joined(separator: ", ")
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedPhrase.colorMode),
                    value: capabilities.supportedModes.map(\.rawValue).joined(separator: ", ")
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedPhrase.bitDepth),
                    value: capabilities.supportedBitDepths.map { "\($0.rawValue)" }.joined(separator: ", ")
                ),
                DiagnosticsReport.Stat(
                    label: text(AppLocalizedPhrase.infrared),
                    value: capabilities.supportsInfrared ? yes : no
                ),
            ]
        } catch {
            report.scannerError = "\(text(AppLocalizedPhrase.capabilityUnavailable)): \(error.localizedDescription)"
        }
    }
}
