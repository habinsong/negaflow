import AppKit
import Chromabase
import SwiftUI

/// 수동 비율 입력(가로 : 세로, 단위 없음). 가로는 필름이 나아가는 방향, 세로는 필름 폭
/// 방향이다. 입력하는 동안에는 적용하지 않고, Enter나 포커스를 벗어날 때 한 번 적용한다.
/// Esc는 입력을 버리고 지금 적용된 값으로 되돌린다.
struct ScanCustomFrameSizeRow: View {
    private enum Field: Hashable { case width, height }

    @EnvironmentObject private var model: AppModel
    @State private var widthDraft = ""
    @State private var heightDraft = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        HStack(spacing: 6) {
            Text(model.text(AppLocalizedPhrase.scanCustomFrameRatio))
            Spacer(minLength: 8)
            field($widthDraft, .width, label: model.text(AppLocalizedPhrase.scanCustomFrameWidth))
            Text(verbatim: ":")
                .foregroundStyle(.secondary)
            field($heightDraft, .height, label: model.text(AppLocalizedPhrase.scanCustomFrameHeight))
        }
        .onAppear(perform: showAppliedRatio)
        .onChange(of: model.scanCustomFrameRatio) { showAppliedRatio() }
        .onChange(of: focusedField) { previous, current in
            // 두 칸 사이를 오가는 동안에는 적용하지 않는다. 칸을 완전히 벗어날 때 적용한다.
            if previous != nil, current == nil { commit() }
        }
    }

    private func field(_ text: Binding<String>, _ field: Field, label: String) -> some View {
        TextField(label, text: text)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .frame(width: 56)
            .focused($focusedField, equals: field)
            // Enter: 칸을 벗어나며 적용한다(적용은 포커스 변화에서 한 번만).
            .onSubmit { focusedField = nil }
            .onExitCommand(perform: cancel)
            .accessibilityLabel(label)
    }

    private func showAppliedRatio() {
        guard let ratio = model.scanCustomFrameRatio else { return }
        widthDraft = FilmFrameRatio.number(ratio.width)
        heightDraft = FilmFrameRatio.number(ratio.height)
    }

    /// Esc: 입력을 버리고 지금 적용된 값으로 되돌린다.
    private func cancel() {
        showAppliedRatio()
        focusedField = nil
    }

    /// 받지 않은 값은 경고음을 내고 입력칸을 지금 적용된 비율로 되돌린다.
    private func commit() {
        guard let width = Self.number(widthDraft), let height = Self.number(heightDraft) else {
            NSSound.beep()
            showAppliedRatio()
            return
        }
        if let applied = model.scanCustomFrameRatio,
           applied.width == width, applied.height == height {
            showAppliedRatio()
            return
        }
        Task {
            if await !model.updateScanCustomFrameRatio(width: width, height: height) {
                NSSound.beep()
            }
            showAppliedRatio()
        }
    }

    /// 쉼표 소수점도 받는다(예: 4,5).
    private static func number(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
