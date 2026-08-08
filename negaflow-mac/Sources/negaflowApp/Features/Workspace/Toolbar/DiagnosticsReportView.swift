import AppKit
import SwiftUI

/// 진단 패널. 종류별 섹션(최근 문제 / 실패 이벤트 / 라이브러리 / 스캐너)을 Liquid Glass 카드로
/// 렌더한다. 모든 카드는 같은 폭·패딩·모서리, 통계 행은 고정 라벨 컬럼으로 값을 세로로 정렬한다.
///
/// **팝오버로 띄우지 않는다.** 여는 버튼이 도구막대 오른쪽 끝이라 팝오버는 창 밖으로 삐져나가
/// 화면 가장자리에서 잘린다. 창 안 오른쪽에 붙여 세로를 꽉 채우면 잘릴 일이 없고, 오른쪽 패널
/// 위를 덮으므로 뒤에 있던 작업 내용도 그대로 남는다.
struct DiagnosticsReportView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var center: DiagnosticsCenter
    var onClose: (() -> Void)?

    // 레이아웃 상수 — 상하좌우·오와열 일정 유지.
    private let contentWidth: CGFloat = 500
    private let outerPadding: CGFloat = 20
    private let sectionSpacing: CGFloat = 14

    private var language: AppLanguage { model.appLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            header
            if let report = center.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        problemsSection(report)
                        eventsSection(report)
                        librarySection(report)
                        scannerSection(report)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(outerPadding)
        .frame(width: contentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .adaptivePanelSurface(.regular)
        .overlay(alignment: .leading) { Divider() }
        .accessibilityIdentifier("negaflow.diagnostics.panel")
    }

    /// 보고서 전체를 사람이 읽는 형태의 한 덩어리 텍스트로 만든다. 붙여넣어 그대로 공유할 수
    /// 있어야 하므로 섹션 제목까지 함께 담는다.
    private func plainText(_ report: DiagnosticsReport) -> String {
        var lines: [String] = [
            model.text(AppLocalizedText.commandDiagnostics),
            generatedLabel(report),
            "",
            model.text(AppLocalizedText.diagnosticsReportProblemsSection),
        ]
        lines += report.problems.isEmpty
            ? [model.text(AppLocalizedText.diagnosticsNoProblems)]
            : report.problems.map { "\(Self.time($0.date))  \($0.message)" }
        lines += ["", model.text(AppLocalizedText.diagnosticsReportEventsSection)]
        lines += report.failureEvents.isEmpty
            ? [model.text(AppLocalizedText.diagnosticsNoProblems)]
            : report.failureEvents.map { "\(Self.time($0.date))  \($0.title)  \($0.code)" }
        lines += ["", model.text(AppLocalizedText.diagnosticsReportLibrarySection)]
        lines += report.libraryStats.map { "\($0.label): \($0.value)" }
        lines += ["", model.text(AppLocalizedText.diagnosticsReportScannerSection)]
        if let scannerError = report.scannerError {
            lines.append(scannerError)
        } else if report.scannerAvailable {
            lines += report.scannerStats.map { "\($0.label): \($0.value)" }
        } else {
            lines.append(model.text(AppLocalizedPhrase.noActiveScanner))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.text(AppLocalizedText.commandDiagnostics))
                .font(.title2.weight(.bold))
            Spacer(minLength: 8)
            if let report = center.report {
                Text(generatedLabel(report))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let report = center.report {
                DiagnosticsCopyButton(
                    text: model.text(AppLocalizedPhrase.copyAll),
                    help: model.text(AppLocalizedPhrase.copyAll)
                ) { plainText(report) }
            }
            Button {
                Task { await model.runDiagnostics() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(center.isGenerating)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(model.text(AppLocalizedPhrase.closePanel))
                .accessibilityLabel(model.text(AppLocalizedPhrase.closePanel))
            }
        }
    }

    // MARK: sections

    private func problemsSection(_ report: DiagnosticsReport) -> some View {
        DiagnosticsSectionCard(
            symbol: "exclamationmark.triangle.fill",
            accent: .red,
            title: model.text(AppLocalizedText.diagnosticsReportProblemsSection),
            count: report.problems.isEmpty ? nil : report.problems.count
        ) {
            if report.problems.isEmpty {
                DiagnosticsEmptyRow(text: model.text(AppLocalizedText.diagnosticsNoProblems))
            } else {
                ForEach(report.problems) { problem in
                    DiagnosticsProblemRow(
                        accent: .red,
                        message: problem.message,
                        time: Self.time(problem.date),
                        copyText: "\(Self.time(problem.date))  \(problem.message)",
                        copyLabel: model.text(AppLocalizedPhrase.copy)
                    )
                }
            }
        }
    }

    private func eventsSection(_ report: DiagnosticsReport) -> some View {
        DiagnosticsSectionCard(
            symbol: "bolt.trianglebadge.exclamationmark.fill",
            accent: .orange,
            title: model.text(AppLocalizedText.diagnosticsReportEventsSection),
            count: report.failureEvents.isEmpty ? nil : report.failureEvents.count
        ) {
            if report.failureEvents.isEmpty {
                DiagnosticsEmptyRow(text: model.text(AppLocalizedText.diagnosticsNoProblems))
            } else {
                ForEach(report.failureEvents) { event in
                    DiagnosticsEventRow(
                        title: event.title,
                        code: event.code,
                        time: Self.time(event.date),
                        copyText: "\(Self.time(event.date))  \(event.title)  \(event.code)",
                        copyLabel: model.text(AppLocalizedPhrase.copy)
                    )
                }
            }
        }
    }

    private func librarySection(_ report: DiagnosticsReport) -> some View {
        DiagnosticsSectionCard(
            symbol: "books.vertical.fill",
            accent: .blue,
            title: model.text(AppLocalizedText.diagnosticsReportLibrarySection),
            count: nil
        ) {
            ForEach(report.libraryStats) { stat in
                DiagnosticsStatRow(
                    label: stat.label,
                    value: stat.value,
                    isWarning: stat.isWarning,
                    copyLabel: model.text(AppLocalizedPhrase.copy)
                )
            }
        }
    }

    private func scannerSection(_ report: DiagnosticsReport) -> some View {
        DiagnosticsSectionCard(
            symbol: "scanner.fill",
            accent: .teal,
            title: model.text(AppLocalizedText.diagnosticsReportScannerSection),
            count: nil
        ) {
            if let scannerError = report.scannerError {
                DiagnosticsProblemRow(
                    accent: .orange,
                    message: scannerError,
                    time: nil,
                    copyText: scannerError,
                    copyLabel: model.text(AppLocalizedPhrase.copy)
                )
            } else if report.scannerAvailable {
                ForEach(report.scannerStats) { stat in
                    DiagnosticsStatRow(
                        label: stat.label,
                        value: stat.value,
                        isWarning: stat.isWarning,
                        copyLabel: model.text(AppLocalizedPhrase.copy)
                    )
                }
            } else {
                DiagnosticsEmptyRow(
                    text: model.text(AppLocalizedPhrase.noActiveScanner),
                    symbol: "scanner",
                    tint: .secondary
                )
            }
        }
    }

    private func generatedLabel(_ report: DiagnosticsReport) -> String {
        model.text(AppLocalizedText.diagnosticsGeneratedAt) + " " + Self.time(report.generatedAt)
    }

    private static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Building blocks (균일 정렬)

/// 하나의 Liquid Glass 섹션 카드. 모든 카드가 같은 헤더 레이아웃·패딩·모서리를 쓴다.
private struct DiagnosticsSectionCard<Content: View>: View {
    let symbol: String
    let accent: Color
    let title: String
    let count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let count {
                    Text(String(count))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(accent)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidSurface(cornerRadius: 16)
    }
}

/// 라벨·값 2열 통계 행. 라벨 컬럼 폭을 고정해 값들이 세로로 정렬된다(오와열).
private struct DiagnosticsStatRow: View {
    let label: String
    let value: String
    var isWarning = false
    var copyLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(isWarning ? Color.orange : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            DiagnosticsCopyButton(help: copyLabel) { "\(label): \(value)" }
        }
    }
}

/// 최근 문제 행: 강조 점 + 메시지(줄바꿈) + 시각(고정 폭, 우측 정렬).
private struct DiagnosticsProblemRow: View {
    let accent: Color
    let message: String
    let time: String?
    var copyText: String
    var copyLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let time {
                Text(time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
            DiagnosticsCopyButton(help: copyLabel) { copyText }
        }
    }
}

/// 실패 이벤트 행: 작업명 + machine code + 시각.
private struct DiagnosticsEventRow: View {
    let title: String
    let code: String
    let time: String
    var copyText: String
    var copyLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            DiagnosticsCopyButton(help: copyLabel) { copyText }
        }
    }
}

/// 한 줄을 클립보드에 담는 단추. 텍스트는 누를 때 만든다 — 행마다 미리 문자열을 만들어 두면
/// 보고서가 길어질수록 그리는 값이 함께 늘어난다.
private struct DiagnosticsCopyButton: View {
    var text: String?
    let help: String
    let content: () -> String

    @State private var didCopy = false

    init(text: String? = nil, help: String, content: @escaping () -> String) {
        self.text = text
        self.help = help
        self.content = content
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content(), forType: .string)
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                if let text {
                    Text(text).font(.caption)
                }
            }
            .foregroundStyle(didCopy ? Color.green : Color.secondary)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 비어 있는 섹션의 긍정 상태 행.
private struct DiagnosticsEmptyRow: View {
    let text: String
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = .green

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
