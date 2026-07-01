import SwiftUI
import Chromabase

struct BaseControlSection: View {
    @ObservedObject var frame: ScanFrame
    let baseMode: Binding<DevelopParameters.BaseMode>
    let manualBaseBinding: (Int) -> Binding<Double>
    /// 필름 Dmin/Dmax 프리셋 ID 바인딩 (preset 모드에서 사용). nil 가능.
    let filmStockDminID: Binding<String?>
    let scannerProfileID: Binding<String?>
    let scannerProfiles: [ScannerProfile]
    let autoMatchScannerProfile: Binding<Bool>
    let autoMatchAction: () -> Void

    private let baseModes: [DevelopParameters.BaseMode] = [.auto, .preset, .manual]

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: "Base", systemImage: "circle.lefthalf.filled")

            SegmentedPicker(
                options: baseModes,
                label: { $0.displayName },
                selection: baseMode
            )
            .disabled(!frame.filmType.requiresInversion)

            if frame.params.baseEstimationMode == .preset {
                InspectorRow("Film Stock") {
                    Picker("Film Stock", selection: filmStockDminID) {
                        Text("선택 안 함").tag(String?.none)
                        ForEach(FilmStockDminRegistry.groupedByManufacturer, id: \.0) { group in
                            Section(header: Text(group.0)) {
                                ForEach(group.1) { stock in
                                    Text("\(stock.displayName)  · ISO \(stock.iso) · \(stock.process)")
                                        .tag(Optional(stock.id))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .disabled(!frame.filmType.requiresInversion)
                }

                InspectorRow("Auto Match") {
                    Toggle("", isOn: autoMatchScannerProfile)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(scannerProfiles.isEmpty)
                        .onChange(of: autoMatchScannerProfile.wrappedValue) { _, enabled in
                            if enabled { autoMatchAction() }
                        }
                }

                InspectorRow("Profile") {
                    Picker("Profile", selection: scannerProfileID) {
                        Text("없음").tag(String?.none)
                        ForEach(scannerProfiles) { profile in
                            Text(profile.displayName).tag(String?.some(profile.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(scannerProfiles.isEmpty)
                }
            }

            if frame.params.baseEstimationMode == .manual {
                InspectorSlider("Base R", value: manualBaseBinding(0), range: 0...1)
                InspectorSlider("Base G", value: manualBaseBinding(1), range: 0...1)
                InspectorSlider("Base B", value: manualBaseBinding(2), range: 0...1)
            }
        }
    }
}

private extension DevelopParameters.BaseMode {
    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .preset:
            return "Film"
        case .manual:
            return "Manual"
        }
    }
}
