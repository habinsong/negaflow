import SwiftUI
import Chromabase

struct ExportFormatOptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.exportFormat {
        case .jpeg:
            LabeledContent(localized(.jpegQuality)) {
                HStack(spacing: 8) {
                    Slider(value: $model.exportJPEGQuality, in: 0...1, step: 0.01)
                    Text(verbatim: "\(Int((model.exportJPEGQuality * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        case .tiff16:
            Picker(localized(.tiffCompression), selection: $model.exportTIFFCompression) {
                Text(localized(.none)).tag(ExportTIFFCompression.none)
                Text(localized(.lzw)).tag(ExportTIFFCompression.lzw)
                Text(localized(.deflate)).tag(ExportTIFFCompression.deflate)
            }
            Picker(localized(.tiffBitDepth), selection: $model.exportTIFFBitDepth) {
                Text(verbatim: "8-bit").tag(ExportBitDepth.eight)
                Text(verbatim: "16-bit").tag(ExportBitDepth.sixteen)
            }
            Toggle(localized(.preserveAlpha), isOn: $model.exportPreserveAlpha)
        case .png:
            Picker(localized(.pngBitDepth), selection: $model.exportPNGBitDepth) {
                Text(verbatim: "8-bit").tag(ExportBitDepth.eight)
                Text(verbatim: "16-bit").tag(ExportBitDepth.sixteen)
            }
            .pickerStyle(.segmented)
            Toggle(localized(.preserveAlpha), isOn: $model.exportPreserveAlpha)
        case .rawScanTIFF:
            EmptyView()
        }
    }

    private func localized(_ text: ExportEncodingLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
