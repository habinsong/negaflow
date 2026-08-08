import SwiftUI
import Chromabase

struct ToolStripSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionDefectMode: Bool
    @AppStorage("crop.aspectLocked") private var isAspectLocked = true
    @State private var aspectPopoverPresented = false

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: model.text(AppLocalizedPhrase.geometry), systemImage: "crop.rotate", trailing: frame.imageTransform.displayName)
            buttonGrid
            if cropMode {
                angleDial
            }
            angleRow
            aspectRow
        }
    }

    // MARK: 종횡비

    static let aspectOptions: [(label: String, ratio: Double?)] = [
        ("original", nil), ("custom", -1),
        ("2:3", 2.0 / 3), ("3:2", 3.0 / 2),
        ("4:3", 4.0 / 3), ("3:4", 3.0 / 4),
        ("4:5", 4.0 / 5), ("5:4", 5.0 / 4),
        ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
        ("16:10", 16.0 / 10), ("10:16", 10.0 / 16),
        ("65:24", 65.0 / 24), ("24:65", 24.0 / 65),
        ("3:1", 3), ("1:3", 1.0 / 3),
        ("1:1", 1),
    ]

    private var currentAspectLabel: String {
        guard let a = frame.imageTransform.cropAspect else {
            return frame.imageTransform.cropRect == nil
                ? model.text(AppLocalizedPhrase.original)
                : model.text(AppLocalizedPhrase.custom)
        }
        let match = Self.aspectOptions.first { opt in
            guard let r = opt.ratio, r > 0 else { return false }
            return abs(r - a) < 1e-3
        }
        return match.map(localizedAspectLabel) ?? model.text(AppLocalizedPhrase.custom)
    }

    private var aspectRow: some View {
        InspectorRow(model.text(AppLocalizedPhrase.aspectRatio)) {
            HStack(spacing: 6) {
                Button {
                    aspectPopoverPresented.toggle()
                } label: {
                    Text(currentAspectLabel)
                        .font(.callout)
                        .frame(maxWidth: 112, alignment: .trailing)
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .popover(isPresented: $aspectPopoverPresented, arrowEdge: .bottom) {
                    LazyVGrid(columns: [GridItem(.fixed(76)), GridItem(.fixed(76))], spacing: 6) {
                        ForEach(Self.aspectOptions, id: \.label) { opt in
                            Button {
                                applyAspectOption(opt)
                                aspectPopoverPresented = false
                            } label: {
                                Text(localizedAspectLabel(opt))
                                    .font(.callout)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                }

                Button {
                    isAspectLocked.toggle()
                } label: {
                    Image(systemName: isAspectLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help(isAspectLocked ? model.text(AppLocalizedPhrase.unlockCropAspect) : model.text(AppLocalizedPhrase.lockCropAspect))
                .accessibilityLabel(isAspectLocked ? model.text(AppLocalizedPhrase.cropAspectLocked) : model.text(AppLocalizedPhrase.cropAspectUnlocked))
            }
        }
    }

    // MARK: 각도(수평 보정)

    private var angleRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(model.text(AppLocalizedPhrase.angle)).font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: frame.imageTransform.straightenAngle,
                    displayText: straightenAngleText(frame.imageTransform.straightenAngle),
                    inputRange: -45...45,
                    inputText: { String(format: "%.1f", $0) },
                    width: 48,
                    onCommit: { model.setStraighten(frame, angle: $0) }
                )
                Button {
                    model.setStraighten(frame, angle: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(abs(frame.imageTransform.straightenAngle) < 1e-4)
            }
            ResettableSlider(
                value: Binding(
                    get: { frame.imageTransform.straightenAngle },
                    set: { model.setStraighten(frame, angle: $0) }
                ),
                in: -45...45,
                resetValue: 0
            )
        }
    }

    var buttonGrid: some View {
        HStack(spacing: 6) {
            ToolIconButton(systemName: "crop", help: model.text(AppLocalizedPhrase.cropArea), isActive: cropMode) {
                withAnimation(.snappy(duration: 0.18)) { cropMode.toggle(); if cropMode { brushMode = false; regionDefectMode = false } }
            }

            ToolDivider()
            ToolIconButton(systemName: "rotate.left", help: model.text(AppLocalizedPhrase.rotateLeft)) {
                model.rotate(frame, clockwise: false)
            }
            ToolIconButton(systemName: "rotate.right", help: model.text(AppLocalizedPhrase.rotateRight)) {
                model.rotate(frame, clockwise: true)
            }
            ToolDivider()
            ToolIconButton(systemName: "arrow.left.and.right", help: model.text(AppLocalizedPhrase.flipHorizontal), isActive: frame.imageTransform.flipHorizontal) {
                model.flipHorizontally(frame)
            }
            ToolIconButton(systemName: "arrow.up.and.down", help: model.text(AppLocalizedPhrase.flipVertical), isActive: frame.imageTransform.flipVertical) {
                model.flipVertically(frame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var angleDial: some View {
        CropAngleDial(angle: frame.imageTransform.straightenAngle) { value in
            model.setStraighten(frame, angle: value)
        } onReset: {
            model.setStraighten(frame, angle: 0)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .center)
        .help(model.text(AppLocalizedPhrase.angle))
        .accessibilityLabel(model.text(AppLocalizedPhrase.angle))
    }

    private func localizedAspectLabel(_ option: (label: String, ratio: Double?)) -> String {
        switch option.label {
        case "original": return model.text(AppLocalizedPhrase.original)
        case "custom": return model.text(AppLocalizedPhrase.custom)
        default: return option.label
        }
    }

    private func applyAspectOption(_ option: (label: String, ratio: Double?)) {
        if option.ratio == -1 {
            frame.updateTransform { $0.cropAspect = nil }
        } else {
            model.applyCropAspect(frame, ratio: option.ratio)
        }
    }

    private func straightenAngleText(_ value: Double) -> String {
        abs(value) < 0.05 ? "0.0°" : String(format: "%+.1f°", value)
    }
}
