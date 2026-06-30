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
        switch self {
        case .shadow: return "Shadow"
        case .density: return "Density"
        case .exposure: return "Exposure"
        case .highlight: return "Highlight"
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

struct InteractiveHistogramView: View {
    let image: NSImage
    @ObservedObject var frame: ScanFrame
    let onChange: () -> Void
    @State private var bins: HistogramBins?
    @State private var hoverRegion: HistogramToneRegion?
    @State private var dragRegion: HistogramToneRegion?
    @State private var dragStartValue: Double?

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
                        Text("Histogram")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let bins, !bins.clippedChannels.isEmpty {
                            Text(bins.clippingText)
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
                            Text(region.title)
                                .font(.system(size: 9, weight: activeRegion == region ? .semibold : .regular))
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
        // `.task(id:)` re-runs on first appearance AND whenever the developed image instance
        // changes, so the histogram repaints immediately instead of waiting for an unrelated
        // re-render (the "click somewhere to make it show up" bug).
        .task(id: ObjectIdentifier(image)) {
            bins = HistogramSampler.compute(image)
        }
    }

    var channelLegend: some View {
        HStack(spacing: 5) {
            Text("RGB")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(HistogramChannel.allCases, id: \.self) { channel in
                Circle()
                    .fill(channel.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(channel.accessibilityLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RGB channel overlay")
    }

    func activeBand(_ region: HistogramToneRegion, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: size.width * (region.upperBound - region.lowerBound), height: size.height)
            .offset(x: size.width * region.lowerBound)
    }

    func valueText(for region: HistogramToneRegion) -> String {
        "\(region.title) \(signedControlText(region.value(in: frame)))"
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

}

enum HistogramChannel: CaseIterable {
    case red
    case green
    case blue

    var title: String {
        switch self {
        case .red: return "R"
        case .green: return "G"
        case .blue: return "B"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .red: return "Red channel"
        case .green: return "Green channel"
        case .blue: return "Blue channel"
        }
    }
}

struct HistogramBins {
    let luma: [Int]
    let r: [Int]
    let g: [Int]
    let b: [Int]
    let totalPixels: Int

    var maxCount: Int {
        [luma.max() ?? 1, r.max() ?? 1, g.max() ?? 1, b.max() ?? 1].max() ?? 1
    }

    var clippedChannels: [HistogramChannel] {
        HistogramChannel.allCases.filter { isClipped($0) }
    }

    var clippingText: String {
        "Clip " + clippedChannels.map(\.title).joined(separator: "/")
    }

    private func isClipped(_ channel: HistogramChannel) -> Bool {
        let data: [Int]
        switch channel {
        case .red: data = r
        case .green: data = g
        case .blue: data = b
        }
        let threshold = max(Int(Double(totalPixels) * 0.002), 1)
        return (data.first ?? 0) > threshold || (data.last ?? 0) > threshold
    }
}

enum HistogramSampler {
    static func compute(_ image: NSImage) -> HistogramBins? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let directImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        let bitmapImage = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.cgImage
        guard let cg = directImage ?? bitmapImage else { return nil }
        let targetW = 256, scale = Double(targetW) / Double(cg.width)
        let targetH = max(1, Int(Double(cg.height) * scale))
        var px = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: targetW, height: targetH, bitsPerComponent: 8,
            bytesPerRow: targetW * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        let nbins = 64
        var luma = [Int](repeating: 0, count: nbins), r = luma, g = luma, b = luma
        for i in stride(from: 0, to: px.count, by: 4) {
            let red = Int(px[i])
            let green = Int(px[i+1])
            let blue = Int(px[i+2])
            let luminance = Int((0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)).rounded())
            luma[luminance * nbins / 256] += 1
            r[red * nbins / 256] += 1
            g[green * nbins / 256] += 1
            b[blue * nbins / 256] += 1
        }
        return HistogramBins(luma: luma, r: r, g: g, b: b, totalPixels: targetW * targetH)
    }
}
