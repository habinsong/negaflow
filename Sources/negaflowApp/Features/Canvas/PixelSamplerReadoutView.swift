import SwiftUI
import Chromabase

struct PixelSamplerReadoutView: View {
    @ObservedObject var store: PixelSamplerStore
    let language: AppLanguage

    var body: some View {
        if store.isEnabled {
            VStack(alignment: .leading, spacing: 5) {
                if let readout = store.readout {
                    Text("\(localized(.sourcePixel))  \(readout.sourceCoordinate.x), \(readout.sourceCoordinate.y)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                    readingRow(localized(.original), reading: readout.original)
                    readingRow(localized(.working), reading: readout.working)
                    readingRow(localized(.proof), reading: readout.proof)
                } else {
                    Label(localized(.movePointer), systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidSurface(cornerRadius: 9)
            .frame(maxWidth: 390, alignment: .leading)
        }
    }

    private func readingRow(_ title: String, reading: PixelColorReading?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(width: 48, alignment: .leading)
            if let reading {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rgbText(reading.rgb))
                    Text(labText(reading.lab))
                }
                .font(.caption2.monospacedDigit())
                Text(reading.colorSpaceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "minus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rgbText(_ rgb: SIMD3<Double>) -> String {
        String(format: "RGB %.3f  %.3f  %.3f", rgb.x, rgb.y, rgb.z)
    }

    private func labText(_ lab: SIMD3<Double>) -> String {
        String(format: "Lab %.1f  %+.1f  %+.1f", lab.x, lab.y, lab.z)
    }

    private func localized(_ text: PixelSamplerLocalizedText) -> String {
        text.resolved(language: language)
    }
}
