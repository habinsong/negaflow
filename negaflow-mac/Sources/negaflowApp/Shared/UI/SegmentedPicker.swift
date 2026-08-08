import SwiftUI

/// 풀폭 균등 분할 세그먼트 컨트롤 — iOS 26 Liquid Glass 세그먼트 룩.
/// 트랙은 은은한 캡슐, 선택 thumb 은 밝은 글래스 면(그림자 없음). 좌우 끝까지 채운다.
struct SegmentedPicker<Value: Hashable>: View {
    @EnvironmentObject private var model: AppModel
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    if option != selection { selection = option }
                } label: {
                    Text(label(option))
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(AppTypography.minimumScaleFactor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.background)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilitySelectionState(
                    isSelected,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
    }
}
