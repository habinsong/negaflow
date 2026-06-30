import SwiftUI
import AppKit
import Chromabase

struct ExportSection: View {
    @EnvironmentObject var model: AppModel

    private let dpiOptions: [Int] = [0, 72, 150, 240, 300, 600]
    private let longEdgeOptions: [Int] = [0, 1024, 2048, 4096, 6000]
    private let quickDPIOptions: [Int] = [72, 150, 240, 300, 600]

    var body: some View {
        Section {
            Picker("Format", selection: $model.exportFormat) {
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
                Text("TIFF 16-bit").tag(ExportFormat.tiff16)
            }

            Picker("Color", selection: $model.exportColorSpace) {
                ForEach(ExportColorSpace.allCases, id: \.self) { space in
                    Text(space.uiLabel).tag(space)
                }
            }

            Picker("DPI", selection: $model.exportDPI) {
                ForEach(dpiOptions, id: \.self) { dpi in
                    Text(dpi == 0 ? "Scan DPI" : "\(dpi) dpi").tag(dpi)
                }
            }

            Picker("Size", selection: $model.exportLongEdge) {
                ForEach(longEdgeOptions, id: \.self) { edge in
                    Text(edge == 0 ? "Full" : "\(edge) px (long edge)").tag(edge)
                }
            }

            Toggle("Sidecar (JSON + XMP)", isOn: $model.exportWriteSidecar)
                .help("현상 파라미터를 <이름>.negaflow.json 과 <이름>.xmp 로 저장")

            if let frame = model.selectedFrame {
                Button {
                    model.exportWithPanel(frame)
                } label: {
                    Text("Export…")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!frame.hasDevelopedOnce)
                .buttonStyle(.borderedProminent)
            }
        } header: {
            sectionHeader("Export", systemImage: "square.and.arrow.up")
        }

        Section {
            Picker("Format", selection: $model.quickExportFormat) {
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
            }

            Picker("DPI", selection: $model.quickExportDPI) {
                ForEach(quickDPIOptions, id: \.self) { dpi in
                    Text("\(dpi) dpi").tag(dpi)
                }
            }

            LabeledContent("Folder") {
                HStack(spacing: 6) {
                    Text(model.quickExportFolderDisplay)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") { chooseQuickExportFolder() }
                        .controlSize(.small)
                }
            }

            if let frame = model.selectedFrame {
                Button {
                    model.quickExport(frame)
                } label: {
                    Label("Quick Export", systemImage: "bolt.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!frame.hasDevelopedOnce)
                .buttonStyle(.bordered)
            }
        } header: {
            sectionHeader("Quick Export", systemImage: "bolt")
        }
    }

    private func chooseQuickExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = model.quickExportFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            model.quickExportFolderPath = url.path
        }
    }
}
