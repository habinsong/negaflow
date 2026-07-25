import SwiftUI

/// 하단 상태바 한 줄 배치 — 선행 슬롯(단계 표시 + 접힘 가능한 진행 텍스트), 중앙 상태 메시지,
/// 후행 컨트롤.
///
/// 창이 좁으면 선행 진행 텍스트("프리뷰 생성 중" 등)와 중앙 상태 메시지가 겹친다. 그때는 중앙
/// 메시지만 남긴다 — 접힌 진행 텍스트는 투명해질 뿐 자리는 유지하므로 측정 폭이 흔들리지 않고
/// (숨김 ↔ 표시 진동 없음) 뒤따르는 컨트롤도 밀리지 않는다.
///
/// StatusMessageCenter 는 이 뷰가 직접 관찰한다 — 메시지 갱신이 ContentView 전체를 무효화하지 않는다.
struct StatusBarMessageRow<Leading: View, Collapsible: View, Trailing: View>: View {
    @ObservedObject var center: StatusMessageCenter
    let isScanning: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let collapsible: () -> Collapsible
    @ViewBuilder let trailing: () -> Trailing

    /// 선행 슬롯과 중앙 메시지 사이 최소 간격.
    private static var minimumGap: CGFloat { 12 }
    /// 중앙 메시지 최대 폭.
    private static var messageMaximumWidth: CGFloat { 320 }

    @State private var messageVisible = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var widths: [StatusBarMessageRowSlot: CGFloat] = [:]

    /// 선행 슬롯 오른쪽 끝이 중앙 메시지 왼쪽 끝을 침범하는가.
    private var collapsesLeading: Bool {
        guard messageVisible,
              let row = widths[.row], row > 0,
              let leadingWidth = widths[.leading],
              let message = widths[.message], message > 0 else { return false }
        return leadingWidth + Self.minimumGap > (row - message) / 2
    }

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    leading()
                    collapsible().opacity(collapsesLeading ? 0 : 1)
                }
                .measuringStatusBarWidth(.leading)
                Spacer()
                trailing()
            }
            if messageVisible {
                Text(center.message)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Self.messageMaximumWidth)
                    .measuringStatusBarWidth(.message)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .measuringStatusBarWidth(.row)
        .onPreferenceChange(StatusBarWidthPreferenceKey.self) { widths = $0 }
        .onChange(of: center.message) { _, _ in scheduleDismissal() }
        .onChange(of: isScanning) { _, _ in scheduleDismissal() }
        .onDisappear { dismissTask?.cancel() }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard !center.message.isEmpty else {
            messageVisible = false
            return
        }
        messageVisible = true
        guard !isScanning else { return }
        let message = center.message
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, center.message == message else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                messageVisible = false
            }
        }
    }
}

// MARK: 폭 측정

private struct StatusBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [StatusBarMessageRowSlot: CGFloat] { [:] }

    static func reduce(value: inout [StatusBarMessageRowSlot: CGFloat],
                       nextValue: () -> [StatusBarMessageRowSlot: CGFloat]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

/// 제네릭 뷰 안에서 중첩 타입을 preference 키로 쓸 수 없어 슬롯 식별자를 파일 스코프로 둔다.
private enum StatusBarMessageRowSlot: Hashable { case row, leading, message }

private extension View {
    func measuringStatusBarWidth(_ slot: StatusBarMessageRowSlot) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: StatusBarWidthPreferenceKey.self,
                                       value: [slot: proxy.size.width])
            }
        )
    }
}
