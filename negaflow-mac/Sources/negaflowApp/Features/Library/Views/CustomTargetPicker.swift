import Chromabase
import SwiftUI

struct CustomTargetPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: DevelopTarget
    @State private var isPresented = false
    @FocusState private var focusedTarget: DevelopTarget?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selection.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(model.text(.customTargetTitle))
        .accessibilityValue(selection.displayName)
        .accessibilityIdentifier("negaflow.develop.custom-target")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(DevelopTarget.customGroups.indices, id: \.self) { group in
                        if group > 0 { Divider() }
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(DevelopTarget.customGroups[group], id: \.self) { target in
                                targetButton(target)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 364, height: 354)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("negaflow.custom.palette")
            .onAppear { focusedTarget = selection }
            .onExitCommand { isPresented = false }
        }
    }

    private func choose(_ target: DevelopTarget) {
        if target != selection { selection = target }
        isPresented = false
    }

    private func handleKey(_ press: KeyPress, target: DevelopTarget) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        let direction: MoveCommandDirection
        switch press.key {
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .return, .space:
            choose(target)
            return .handled
        case .escape:
            isPresented = false
            return .handled
        default: return .ignored
        }
        focusedTarget = CustomTargetNavigation.moved(from: target, direction: direction)
        return .handled
    }

    private func targetButton(_ target: DevelopTarget) -> some View {
        Button {
            choose(target)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .opacity(target == selection ? 1 : 0)
                    .frame(width: 12)
                Text(target.displayName)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background {
                if target == selection {
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedTarget, equals: target)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleKey(press, target: target)
        }
        .accessibilityIdentifier("negaflow.custom.target.\(target.rawValue)")
        .accessibilityLabel(target.displayName)
        .accessibilitySelectionState(
            target == selection,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}

enum CustomTargetNavigation {
    static let rows: [[DevelopTarget]] = DevelopTarget.customGroups.flatMap { group in
        stride(from: 0, to: group.count, by: 2).map {
            Array(group[$0..<min($0 + 2, group.count)])
        }
    }

    static func moved(from target: DevelopTarget, direction: MoveCommandDirection) -> DevelopTarget {
        guard let row = rows.firstIndex(where: { $0.contains(target) }),
              let column = rows[row].firstIndex(of: target) else { return target }
        switch direction {
        case .left: return rows[row][max(0, column - 1)]
        case .right: return rows[row][min(rows[row].count - 1, column + 1)]
        case .up:
            let next = max(0, row - 1)
            return rows[next][min(column, rows[next].count - 1)]
        case .down:
            let next = min(rows.count - 1, row + 1)
            return rows[next][min(column, rows[next].count - 1)]
        @unknown default: return target
        }
    }
}
