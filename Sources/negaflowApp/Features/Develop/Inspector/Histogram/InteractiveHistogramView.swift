import SwiftUI
import AppKit
import Chromabase

@MainActor
enum HistogramToneRegion: CaseIterable {
    case shadow
    case density
    case exposure
    case highlight

    var title: String {
        title(language: .system)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .shadow: return AppLocalization.text(AppLocalizedPhrase.shadowTone, language: language)
        case .density: return AppLocalization.text(AppLocalizedPhrase.density, language: language)
        case .exposure: return AppLocalization.text(AppLocalizedPhrase.exposure, language: language)
        case .highlight: return AppLocalization.text(AppLocalizedPhrase.highlightTone, language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .shadow: return "moon.fill"
        case .density: return "circle.lefthalf.filled"
        case .exposure: return "plusminus.circle"
        case .highlight: return "sun.max.fill"
        }
    }

    var lowerBound: CGFloat {
        switch self {
        case .shadow: return 0.00
        case .density: return 0.26
        case .exposure: return 0.50
        case .highlight: return 0.74
        }
    }

    var upperBound: CGFloat {
        switch self {
        case .shadow: return 0.26
        case .density: return 0.50
        case .exposure: return 0.74
        case .highlight: return 1.00
        }
    }

    var sensitivity: Double {
        switch self {
        case .exposure: return 4.0
        default: return 2.0
        }
    }

    var limits: ClosedRange<Double> {
        switch self {
        case .exposure: return -2...2
        default: return -1...1
        }
    }

    func contains(_ unitX: CGFloat) -> Bool {
        unitX >= lowerBound && unitX < upperBound
    }

    func value(in frame: ScanFrame) -> Double {
        switch self {
        case .shadow: return frame.params.shadow
        case .density: return frame.params.density
        case .exposure: return frame.params.exposure
        case .highlight: return frame.params.highlight
        }
    }

    func apply(to frame: ScanFrame, value: Double) {
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        frame.updateParams { params in
            switch self {
            case .shadow: params.shadow = clamped
            case .density: params.density = clamped
            case .exposure: params.exposure = clamped
            case .highlight: params.highlight = clamped
            }
        }
    }

    static func region(at x: CGFloat, width: CGFloat) -> HistogramToneRegion {
        let unitX = min(max(x / max(width, 1), 0), 0.999)
        return allCases.first { $0.contains(unitX) } ?? .exposure
    }
}
/// `.task(id:)` 비교용 이미지 identity. 강한 참조를 보유해 비교 시점까지 이전 이미지가
/// 살아 있게 한다 — 주소 재사용으로 다른 이미지가 같은 id 로 판정되는 일이 없다.
struct HistogramImageIdentity: Equatable {
    let image: NSImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.image === rhs.image }
}

struct InteractiveHistogramView: View {
    @EnvironmentObject private var model: AppModel
    let image: NSImage
    @ObservedObject var frame: ScanFrame
    let onChange: () -> Void
    @State private var bins: HistogramBins?
    @State private var hoverRegion: HistogramToneRegion?
    @State private var dragRegion: HistogramToneRegion?
    @State private var dragStartValue: Double?
    @State private var accessibilityRegion: HistogramToneRegion = .exposure

    init(image: NSImage, frame: ScanFrame, onChange: @escaping () -> Void) {
        self.image = image
        self._frame = ObservedObject(wrappedValue: frame)
        self.onChange = onChange
    }

    var body: some View {
        GeometryReader { geo in
            let activeRegion = dragRegion ?? hoverRegion
            ZStack(alignment: .bottomLeading) {
                if let activeRegion {
                    activeBand(activeRegion, size: geo.size)
                }
                Canvas { ctx, size in
                    let plot = CGRect(x: 8, y: 24, width: max(1, size.width - 16), height: max(1, size.height - 50))
                    var background = Path()
                    background.addRoundedRect(in: plot, cornerSize: CGSize(width: 8, height: 8))
                    ctx.fill(background, with: .color(Color.black.opacity(0.22)))
                    guard let bins = bins else { return }
                    let n = bins.luma.count
                    let bw = plot.width / CGFloat(n)
                    let peak = CGFloat(max(bins.maxCount, 1))
                    for region in HistogramToneRegion.allCases.dropFirst() {
                        let x = plot.minX + plot.width * region.lowerBound
                        var divider = Path()
                        divider.move(to: CGPoint(x: x, y: plot.minY))
                        divider.addLine(to: CGPoint(x: x, y: plot.maxY))
                        ctx.stroke(divider, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                    }
                    for fraction in [0.25, 0.50, 0.75] {
                        let y = plot.maxY - plot.height * CGFloat(fraction)
                        var line = Path()
                        line.move(to: CGPoint(x: plot.minX, y: y))
                        line.addLine(to: CGPoint(x: plot.maxX, y: y))
                        ctx.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                    }
                    func yPosition(_ value: Int) -> CGFloat {
                        let unit = sqrt(CGFloat(value) / peak)
                        return plot.maxY - unit * plot.height
                    }
                    func drawArea(_ data: [Int], _ color: Color) {
                        var path = Path()
                        for (i, v) in data.enumerated() {
                            let x = plot.minX + CGFloat(i) * bw
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: plot.maxY))
                                path.addLine(to: CGPoint(x: x, y: yPosition(v)))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: yPosition(v)))
                            }
                        }
                        path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(color))
                    }
                    func drawLine(_ data: [Int], _ color: Color) {
                        var path = Path()
                        for (i, v) in data.enumerated() {
                            let x = plot.minX + CGFloat(i) * bw
                            let y = yPosition(v)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        ctx.stroke(path, with: .color(color), lineWidth: 1.35)
                    }
                    drawArea(bins.luma, Color.white.opacity(0.14))
                    drawLine(bins.luma, Color.white.opacity(0.40))
                    drawLine(bins.r, .red.opacity(0.88))
                    drawLine(bins.g, .green.opacity(0.82))
                    drawLine(bins.b, .blue.opacity(0.88))
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(model.text(AppLocalizedPhrase.histogram))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let bins, !bins.clippedChannels.isEmpty {
                            Text(bins.clippingText(language: model.appLanguage))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        channelLegend
                        if let activeRegion {
                            Label(valueText(for: activeRegion), systemImage: activeRegion.symbolName)
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(HistogramToneRegion.allCases, id: \.self) { region in
                            Text(region.title(language: model.appLanguage))
                                .font(AppTypography.minimumText(
                                    weight: activeRegion == region ? .semibold : .regular
                                ))
                                .foregroundStyle(activeRegion == region ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(8)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geo.size.width))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverRegion = HistogramToneRegion.region(at: location.x, width: geo.size.width)
                case .ended:
                    hoverRegion = nil
                }
            }
        }
        .frame(height: 118)
        .liquidSurface(cornerRadius: 14, interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.text(AppLocalizedPhrase.histogram))
        .accessibilityValue(valueText(for: accessibilityRegion))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustAccessibilityRegion(1)
            case .decrement: adjustAccessibilityRegion(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(model.accessibilityText(.previousRegion))) {
            selectAccessibilityRegion(-1)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.nextRegion))) {
            selectAccessibilityRegion(1)
        }
        .focusable()
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in
            selectAccessibilityRegion(-1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in
            selectAccessibilityRegion(1)
            return .handled
        }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
            adjustAccessibilityRegion(press.modifiers.contains(.shift) ? 5 : 1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
            adjustAccessibilityRegion(press.modifiers.contains(.shift) ? -5 : -1)
            return .handled
        }
        // `.task(id:)` re-runs on first appearance AND whenever the developed image instance
        // changes, so the histogram repaints immediately instead of waiting for an unrelated
        // re-render (the "click somewhere to make it show up" bug).
        // id 는 강한 참조를 품은 identity 여야 한다: ObjectIdentifier(주소)만 저장하면 이전
        // 이미지가 해제된 뒤 새 이미지가 같은 주소를 재사용할 때 id 가 같아져 태스크가
        // 재실행되지 않는다(stale 히스토그램).
        .task(id: HistogramImageIdentity(image: image)) {
            bins = HistogramSampler.compute(image)
        }
    }

    var channelLegend: some View {
        HStack(spacing: 5) {
            Text(model.text(AppLocalizedPhrase.rgb))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(HistogramChannel.allCases, id: \.self) { channel in
                Circle()
                    .fill(channel.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(channel.accessibilityLabel(language: model.appLanguage))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.text(AppLocalizedPhrase.rgbChannelOverlay))
    }

    func activeBand(_ region: HistogramToneRegion, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: size.width * (region.upperBound - region.lowerBound), height: size.height)
            .offset(x: size.width * region.lowerBound)
    }

    func valueText(for region: HistogramToneRegion) -> String {
        "\(region.title(language: model.appLanguage)) \(signedControlText(region.value(in: frame)))"
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let region = dragRegion ?? HistogramToneRegion.region(at: value.startLocation.x, width: width)
                if dragRegion == nil {
                    dragRegion = region
                    dragStartValue = region.value(in: frame)
                }
                guard let dragStartValue else { return }
                let delta = Double(value.translation.width / max(width, 1)) * region.sensitivity
                region.apply(to: frame, value: dragStartValue + delta)
                onChange()
            }
            .onEnded { _ in
                dragRegion = nil
                dragStartValue = nil
            }
    }

    private func selectAccessibilityRegion(_ offset: Int) {
        let regions = HistogramToneRegion.allCases
        guard let index = regions.firstIndex(of: accessibilityRegion) else { return }
        accessibilityRegion = regions[min(max(index + offset, 0), regions.count - 1)]
    }

    private func adjustAccessibilityRegion(_ steps: Int) {
        let unit = accessibilityRegion == .exposure ? 0.05 : 0.02
        accessibilityRegion.apply(
            to: frame,
            value: accessibilityRegion.value(in: frame) + Double(steps) * unit
        )
        onChange()
    }

}
