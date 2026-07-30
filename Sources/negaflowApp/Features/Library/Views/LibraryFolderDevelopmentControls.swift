import Chromabase
import SwiftUI

struct LibraryFolderDevelopmentControls: View {
    @EnvironmentObject private var model: AppModel

    let frames: [ScanFrame]

    @State private var process: DevelopmentProcess
    @State private var target: DevelopTarget
    @State private var progress: LibraryTaskProgress?
    @State private var isApplying = false
    @State private var progressID: UUID?

    init(
        frames: [ScanFrame],
        fallbackProcess: DevelopmentProcess,
        fallbackTarget: DevelopTarget
    ) {
        self.frames = frames
        _process = State(initialValue: frames.first.map {
            DevelopmentProcess(
                filmType: $0.filmType,
                isDigitalSource: $0.params.isDigitalSource
            )
        } ?? fallbackProcess)
        _target = State(initialValue: frames.first?.params.developTarget ?? fallbackTarget)
    }

    var body: some View {
        HStack(spacing: 7) {
            LibraryFolderBatchPicker(
                title: process.displayName,
                help: model.text(AppLocalizedPhrase.process),
                width: 98,
                options: DevelopmentProcess.allCases,
                selection: $process,
                optionTitle: \.displayName
            )

            LibraryFolderBatchPicker(
                title: target.displayName(language: model.appLanguage),
                help: model.text(AppLocalizedPhrase.target),
                width: 84,
                options: Self.visibleTargets,
                selection: $target,
                optionTitle: { $0.displayName(language: model.appLanguage) }
            )

            LibraryFolderApplyButton(
                title: model.text(AppLocalizedPhrase.apply),
                isDisabled: frames.isEmpty || isApplying
            ) {
                let requestID = UUID()
                progressID = requestID
                isApplying = true
                model.applyLibraryFolderDevelopment(
                    process: process,
                    target: target,
                    frames: frames,
                    progress: { update in
                        progress = update
                        if update.completedCount == update.totalCount {
                            isApplying = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.2))
                                guard !Task.isCancelled,
                                      progressID == requestID,
                                      !isApplying else { return }
                                progress = nil
                            }
                        }
                    }
                )
            }

            if let progress {
                LibraryTaskProgressView(progress: progress, barWidth: 60)
                    .transition(.opacity)
            }
        }
        .controlSize(.regular)
        .font(.callout)
        .disabled(frames.isEmpty)
    }

    private static let visibleTargets: [DevelopTarget] = [
        .main, .noritsu, .sp3000, .f135, .hr,
    ]
}

struct LibraryTaskProgressView: View {
    let progress: LibraryTaskProgress
    var barWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress.fraction)
                .frame(width: barWidth)
                .frame(maxWidth: barWidth == nil ? .infinity : nil)
            Text(verbatim: "\(progress.percent)%")
                .frame(minWidth: 30, alignment: .trailing)
            Text(verbatim: "\(progress.completedCount)/\(progress.totalCount)")
                .frame(minWidth: 38, alignment: .trailing)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(progress.percent)%, \(progress.completedCount)/\(progress.totalCount)"
        )
    }
}

private struct LibraryFolderBatchPicker<Option: Hashable>: View {
    let title: String
    let help: String
    let width: CGFloat
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 30)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        isPresented = false
                    } label: {
                        HStack {
                            Text(optionTitle(option))
                            Spacer(minLength: 12)
                            if option == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 28)
                }
            }
            .padding(6)
            .frame(minWidth: max(width + 48, 150))
            // 팝오버가 열릴 때 첫 항목이 초기 포커스를 받아 파란 테두리가 그려진다.
            // 목록에서 고르는 UI라 포커스 표시가 선택으로 오해된다.
            .focusEffectDisabled()
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(title)
    }
}

private struct LibraryFolderApplyButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Color.primary.opacity(isDisabled ? 0 : 0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("negaflow.library.folder-develop-apply")
    }
}
