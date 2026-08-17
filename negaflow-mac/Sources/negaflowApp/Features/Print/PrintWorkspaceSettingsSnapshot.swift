import Chromabase
import Foundation

// MARK: - 인화 작업공간 설정 스냅샷
//
// 용지·여백·레이아웃·패키지 배치·C 프린트 설정까지 인화 화면에서 사용자가 바꾸는 값 전부.
// 되돌리기는 개별 컨트롤이 아니라 이 한 덩어리를 왕복시킨다 — 컨트롤이 늘어도 따라온다.
struct PrintWorkspaceSettingsSnapshot: Equatable {
    var paperSize: PrintPaperSize
    var orientation: PrintPaperOrientation
    var marginMM: Double
    var perforationStyle: PrintPerforationStyle
    var layoutMode: PrintWorkspaceLayoutMode
    var sheetColor: PrintContactSheetBackground
    var paperSurface: PrintPaperSurface
    var showsRulers: Bool
    var rulerUnit: PrintRulerUnit
    var packageSettings: PrintPackageSettings
    var outputProcess: PrintOutputProcess
    var cPrintLabName: String
    var cPrintPaperName: String
    var cPrintProofICCProfileData: Data?
    var cPrintProofICCProfileName: String?
    var cPrintPreviewEnabled: Bool
    var cPrintPaperSimulationEnabled: Bool
}

extension PrintWorkspaceSettingsStore {
    var snapshot: PrintWorkspaceSettingsSnapshot {
        PrintWorkspaceSettingsSnapshot(
            paperSize: paperSize,
            orientation: orientation,
            marginMM: marginMM,
            perforationStyle: perforationStyle,
            layoutMode: layoutMode,
            sheetColor: sheetColor,
            paperSurface: paperSurface,
            showsRulers: showsRulers,
            rulerUnit: rulerUnit,
            packageSettings: packageSettings,
            outputProcess: outputProcess,
            cPrintLabName: cPrintLabName,
            cPrintPaperName: cPrintPaperName,
            cPrintProofICCProfileData: cPrintProofICCProfileData,
            cPrintProofICCProfileName: cPrintProofICCProfileName,
            cPrintPreviewEnabled: cPrintPreviewEnabled,
            cPrintPaperSimulationEnabled: cPrintPaperSimulationEnabled
        )
    }

    /// 스냅샷을 되돌려 넣는다. 값이 실제로 다른 항목만 대입해 저장·정규화 didSet 이 필요 이상으로
    /// 돌지 않게 한다.
    func restore(_ snapshot: PrintWorkspaceSettingsSnapshot) {
        if paperSize != snapshot.paperSize { paperSize = snapshot.paperSize }
        if orientation != snapshot.orientation { orientation = snapshot.orientation }
        if marginMM != snapshot.marginMM { marginMM = snapshot.marginMM }
        if perforationStyle != snapshot.perforationStyle { perforationStyle = snapshot.perforationStyle }
        if layoutMode != snapshot.layoutMode { layoutMode = snapshot.layoutMode }
        if sheetColor != snapshot.sheetColor { sheetColor = snapshot.sheetColor }
        if paperSurface != snapshot.paperSurface { paperSurface = snapshot.paperSurface }
        if showsRulers != snapshot.showsRulers { showsRulers = snapshot.showsRulers }
        if rulerUnit != snapshot.rulerUnit { rulerUnit = snapshot.rulerUnit }
        if packageSettings != snapshot.packageSettings { packageSettings = snapshot.packageSettings }
        if outputProcess != snapshot.outputProcess { outputProcess = snapshot.outputProcess }
        if cPrintLabName != snapshot.cPrintLabName { cPrintLabName = snapshot.cPrintLabName }
        if cPrintPaperName != snapshot.cPrintPaperName { cPrintPaperName = snapshot.cPrintPaperName }
        if cPrintProofICCProfileData != snapshot.cPrintProofICCProfileData {
            cPrintProofICCProfileData = snapshot.cPrintProofICCProfileData
        }
        if cPrintProofICCProfileName != snapshot.cPrintProofICCProfileName {
            cPrintProofICCProfileName = snapshot.cPrintProofICCProfileName
        }
        if cPrintPreviewEnabled != snapshot.cPrintPreviewEnabled {
            cPrintPreviewEnabled = snapshot.cPrintPreviewEnabled
        }
        if cPrintPaperSimulationEnabled != snapshot.cPrintPaperSimulationEnabled {
            cPrintPaperSimulationEnabled = snapshot.cPrintPaperSimulationEnabled
        }
    }
}
