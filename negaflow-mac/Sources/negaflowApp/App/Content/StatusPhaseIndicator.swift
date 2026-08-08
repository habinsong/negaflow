import SwiftUI
import ScannerKit

/// 상태바 좌측: 상태 점 + 단계 텍스트.
///
/// - 점: 최근 오류가 있으면 빨강(지속) — 클릭하면 최근 오류 목록 팝오버, 호버하면 최신 오류 툴팁.
///   오류가 없으면 단계 색(완료=초록/대기=회색/그 외=파랑)이고 상호작용하지 않는다.
/// - 단계 텍스트: 단계가 바뀌면 이름을 띄우고 **3초 뒤 사라진다**(토스트와 동일). 상태가 계속
///   붙어 있으면 하단 바가 늘 지저분하고 중앙 메시지와 겹칠 여지도 커진다. 새 단계나 새 오류가
///   들어오면 다시 표시되고 타이머가 재시작된다. 폭(92pt)은 유지해 진행 슬롯이 안 밀린다.
struct StatusPhaseIndicator: View {
    let phase: ScanPhase
    let language: AppLanguage
    @ObservedObject var errorLog: AppErrorLog

    @State private var phaseTextVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showPopover = false

    private var dotColor: Color {
        if errorLog.hasEntries { return .red }
        switch phase {
        case .complete: return .green
        case .idle, .error: return .gray
        default: return .blue
        }
    }

    private var hoverHelp: String {
        errorLog.latest?.message
            ?? AppLocalization.text(.diagnosticsNoProblems, language: language)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(4)                       // 클릭·호버 히트 영역 확대
                .contentShape(Rectangle())
                .onTapGesture {
                    if errorLog.hasEntries { showPopover.toggle() }
                }
                .help(hoverHelp)
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    RecentErrorsPopover(errorLog: errorLog, language: language)
                }
                .accessibilityLabel(hoverHelp)
                .padding(-4)                      // 레이아웃 상 원래 크기 유지

            phaseText
                .frame(width: 92, alignment: .leading)
        }
        .onAppear { applyPhase(phase) }
        .onChange(of: phase) { _, newPhase in applyPhase(newPhase) }
        .onChange(of: errorLog.entries.count) { _, _ in
            // 이미 .error 상태에서 새 오류가 들어오면(phase 값은 그대로) 텍스트를 다시 띄우고 재시작.
            if phase == .error {
                phaseTextVisible = true
                scheduleHide()
            }
        }
    }

    @ViewBuilder
    private var phaseText: some View {
        if !phaseTextVisible {
            Color.clear.frame(height: 1)
        } else {
            Text(phase.displayName(language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private func applyPhase(_ phase: ScanPhase) {
        hideTask?.cancel()
        phaseTextVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { phaseTextVisible = false }
        }
    }
}

/// 상태 점 클릭 시 뜨는 최근 오류 목록.
struct RecentErrorsPopover: View {
    @ObservedObject var errorLog: AppErrorLog
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppLocalization.text(.diagnosticsRecentProblemsTitle, language: language))
                    .font(.headline)
                Spacer(minLength: 12)
                Button {
                    errorLog.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text(.diagnosticsClearProblems, language: language))
                .disabled(!errorLog.hasEntries)
            }
            Divider()
            if errorLog.entries.isEmpty {
                Text(AppLocalization.text(.diagnosticsNoProblems, language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(errorLog.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(entry.date, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
