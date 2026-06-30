import SwiftUI
import Chromabase

struct ToolStripSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionICEMode: Bool

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: "Geometry", systemImage: "crop.rotate", trailing: frame.imageTransform.displayName)
            buttons
            aspectRow
            angleRow
        }
    }

    // MARK: 종횡비

    static let aspectOptions: [(label: String, ratio: Double?)] = [
        ("원본", nil), ("사용자 정의", -1),
        ("1:1", 1), ("2:3", 2.0 / 3), ("3:2", 3.0 / 2), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4),
        ("4:5", 4.0 / 5), ("5:4", 5.0 / 4), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
        ("16:10", 16.0 / 10), ("10:16", 10.0 / 16), ("65:24", 65.0 / 24), ("24:65", 24.0 / 65),
        ("3:1", 3), ("1:3", 1.0 / 3),
    ]

    private var currentAspectLabel: String {
        guard let a = frame.imageTransform.cropAspect else {
            return frame.imageTransform.cropRect == nil ? "원본" : "사용자 정의"
        }
        let match = Self.aspectOptions.first { opt in
            guard let r = opt.ratio, r > 0 else { return false }
            return abs(r - a) < 1e-3
        }
        return match?.label ?? "사용자 정의"
    }

    private var aspectRow: some View {
        InspectorRow("Aspect Ratio") {
            Menu {
                ForEach(Self.aspectOptions, id: \.label) { opt in
                    Button(opt.label) {
                        if opt.ratio == -1 {            // 사용자 정의: 종횡비 잠금 해제(자유 크롭)
                            frame.updateTransform { $0.cropAspect = nil }
                        } else {
                            model.applyCropAspect(frame, ratio: opt.ratio)
                        }
                    }
                }
            } label: {
                Text(currentAspectLabel)
                    .font(.callout)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isScanning)
        }
    }

    // MARK: 각도(수평 보정)

    private var angleRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Angle").font(.caption)
                Spacer()
                Text(String(format: "%+.1f°", frame.imageTransform.straightenAngle))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Button {
                    model.setStraighten(frame, angle: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(abs(frame.imageTransform.straightenAngle) < 1e-4)
            }
            Slider(
                value: Binding(
                    get: { frame.imageTransform.straightenAngle },
                    set: { model.setStraighten(frame, angle: $0) }
                ),
                in: -45...45
            )
        }
    }

    var buttons: some View {
        HStack(spacing: 6) {
            ToolIconButton(systemName: "paintbrush.pointed.fill", help: "결함 브러시 — 먼지/스크래치 위를 칠하면 그 안에서만 제거", isActive: brushMode) {
                withAnimation(.snappy(duration: 0.18)) { brushMode.toggle(); if brushMode { cropMode = false; regionICEMode = false } }
            }

            ToolIconButton(systemName: "scope", help: "영역 ICE — 영역을 드래그하면 결함을 자동 검출(빨강), 클릭 제외 후 제거", isActive: regionICEMode) {
                withAnimation(.snappy(duration: 0.18)) {
                    regionICEMode.toggle()
                    if regionICEMode { cropMode = false; brushMode = false } else { model.cancelRegionICE(frame) }
                }
            }

            ToolIconButton(systemName: "crop", help: "크롭 영역", isActive: cropMode) {
                withAnimation(.snappy(duration: 0.18)) { cropMode.toggle(); if cropMode { brushMode = false; regionICEMode = false } }
            }

            ToolIconButton(systemName: "rotate.left", help: "왼쪽으로 90도 회전") {
                model.rotate(frame, clockwise: false)
            }
            ToolIconButton(systemName: "rotate.right", help: "오른쪽으로 90도 회전") {
                model.rotate(frame, clockwise: true)
            }

            ToolIconButton(systemName: "arrow.left.and.right", help: "좌우 반전", isActive: frame.imageTransform.flipHorizontal) {
                model.flipHorizontally(frame)
            }
            ToolIconButton(systemName: "arrow.up.and.down", help: "상하 반전", isActive: frame.imageTransform.flipVertical) {
                model.flipVertically(frame)
            }

            Button {
                cropMode = false
                model.resetTransform(frame)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .disabled(frame.imageTransform.isIdentity && model.nextScanOrientation.isIdentity && !cropMode)
            .opacity(frame.imageTransform.isIdentity && model.nextScanOrientation.isIdentity && !cropMode ? 0.35 : 1)
            .help("변형 초기화")
            .accessibilityLabel("변형 초기화")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ToolIconButton: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 36, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}
