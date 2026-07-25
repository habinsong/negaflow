import Combine
import Foundation
import SwiftUI
import AppKit
import Chromabase

enum WorkflowShortcutGroup: CaseIterable, Identifiable {
    case library
    case photo
    case develop
    case view
    case scanner
    case export
    case help

    var id: Self { self }

    var titleKey: AppLocalizedText {
        switch self {
        case .library: return .menuLibrary
        case .photo: return .menuPhoto
        case .develop: return .menuDevelop
        case .view: return .menuView
        case .scanner: return .menuScanner
        case .export: return .menuExport
        case .help: return .menuHelp
        }
    }

    var systemImage: String {
        let imageName: String
        switch self {
        case .library: imageName = "rectangle.stack"
        case .photo: imageName = "photo"
        case .develop: imageName = "slider.horizontal.3"
        case .view: imageName = "sidebar.left"
        case .scanner: imageName = "scanner"
        case .export: imageName = "square.and.arrow.up"
        case .help: imageName = "questionmark.circle"
        }
        return imageName
    }
}

enum WorkflowShortcutAction: String, CaseIterable, Codable, Identifiable {
    case importImages
    case importFolder
    case refreshLibrary
    case loadScanner
    case libraryGrid
    case libraryCompare
    case librarySurvey
    case previousPhoto
    case nextPhoto
    case pickPhoto
    case clearPick
    case rejectPhoto
    case deletePhoto
    case rateZero
    case rateOne
    case rateTwo
    case rateThree
    case rateFour
    case rateFive
    case createVirtualCopy
    case autoTone
    case autoWhiteBalance
    case toggleAutoColor
    case toggleAutoLevels
    case toggleNoiseReduction
    case resetAdjustments
    case copyDevelopSettings
    case pasteDevelopSettings
    case processColorNegative
    case processColorPositive
    case processBWNegative
    case processBWPositive
    case targetMain
    case targetPrint
    case targetHS
    case targetSP
    case targetF135
    case targetHR
    case targetExpired
    case cropTool
    case basePickerTool
    case autoDefectTool
    case guidedDefectTool
    case brushDefectTool
    case cloneStampTool
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical
    case toggleBeforeAfter
    case showHideSidebar
    case showHideFilmstrip
    case showHideInspector
    case toggleFullScreen
    case openLibraryWorkspace
    case openDevelopWorkspace
    case openPrintWorkspace
    case detectScanners
    case toggleScannerSimulator
    case previewScan
    case scanFrame
    case quickExport
    case exportPhoto
    case openHelp

    var id: Self { self }

    var group: WorkflowShortcutGroup {
        switch self {
        case .importImages, .importFolder, .refreshLibrary, .loadScanner,
             .libraryGrid, .libraryCompare, .librarySurvey:
            return .library
        case .previousPhoto, .nextPhoto, .pickPhoto, .clearPick, .rejectPhoto,
             .deletePhoto, .rateZero, .rateOne, .rateTwo, .rateThree, .rateFour, .rateFive,
             .createVirtualCopy:
            return .photo
        case .autoTone, .autoWhiteBalance, .toggleAutoColor, .toggleAutoLevels,
             .toggleNoiseReduction, .resetAdjustments, .copyDevelopSettings,
             .pasteDevelopSettings, .processColorNegative, .processColorPositive,
             .processBWNegative, .processBWPositive, .targetMain, .targetPrint, .targetHS,
             .targetSP, .targetF135, .targetHR, .targetExpired, .cropTool, .basePickerTool,
             .autoDefectTool, .guidedDefectTool, .brushDefectTool, .cloneStampTool,
             .rotateLeft, .rotateRight, .flipHorizontal, .flipVertical, .toggleBeforeAfter:
            return .develop
        case .showHideSidebar, .showHideFilmstrip, .showHideInspector, .toggleFullScreen,
             .openLibraryWorkspace, .openDevelopWorkspace, .openPrintWorkspace:
            return .view
        case .detectScanners, .toggleScannerSimulator, .previewScan, .scanFrame:
            return .scanner
        case .quickExport, .exportPhoto:
            return .export
        case .openHelp:
            return .help
        }
    }

    var defaultShortcut: WorkflowShortcut {
        switch self {
        case .importImages: return WorkflowShortcut(key: "i", modifiers: [.command])
        case .importFolder: return WorkflowShortcut(key: "i", modifiers: [.command, .shift])
        case .refreshLibrary: return WorkflowShortcut(key: "r", modifiers: [.command])
        case .loadScanner: return WorkflowShortcut(key: "l", modifiers: [.command, .option])
        case .libraryGrid: return WorkflowShortcut(key: "g", modifiers: [])
        case .libraryCompare: return WorkflowShortcut(key: "c", modifiers: [])
        case .librarySurvey: return WorkflowShortcut(key: "n", modifiers: [])
        case .previousPhoto: return WorkflowShortcut(key: "[", modifiers: [])
        case .nextPhoto: return WorkflowShortcut(key: "]", modifiers: [])
        case .pickPhoto: return WorkflowShortcut(key: "p", modifiers: [])
        case .clearPick: return WorkflowShortcut(key: "u", modifiers: [])
        case .rejectPhoto: return WorkflowShortcut(key: "x", modifiers: [])
        case .deletePhoto: return WorkflowShortcut(key: "delete", modifiers: [])
        case .rateZero: return WorkflowShortcut(key: "0", modifiers: [])
        case .rateOne: return WorkflowShortcut(key: "1", modifiers: [])
        case .rateTwo: return WorkflowShortcut(key: "2", modifiers: [])
        case .rateThree: return WorkflowShortcut(key: "3", modifiers: [])
        case .rateFour: return WorkflowShortcut(key: "4", modifiers: [])
        case .rateFive: return WorkflowShortcut(key: "5", modifiers: [])
        case .createVirtualCopy: return WorkflowShortcut(key: "'", modifiers: [.command])
        case .autoTone: return WorkflowShortcut(key: "u", modifiers: [.command])
        case .autoWhiteBalance: return WorkflowShortcut(key: "u", modifiers: [.command, .shift])
        case .toggleAutoColor: return WorkflowShortcut(key: "b", modifiers: [.command, .shift])
        case .toggleAutoLevels: return WorkflowShortcut(key: "l", modifiers: [.command, .shift])
        case .toggleNoiseReduction: return WorkflowShortcut(key: "n", modifiers: [.command, .option])
        case .resetAdjustments: return WorkflowShortcut(key: "r", modifiers: [.command, .shift])
        case .copyDevelopSettings: return WorkflowShortcut(key: "c", modifiers: [.command, .shift])
        case .pasteDevelopSettings: return WorkflowShortcut(key: "v", modifiers: [.command, .shift])
        case .processColorNegative: return WorkflowShortcut(key: "1", modifiers: [.control, .shift])
        case .processColorPositive: return WorkflowShortcut(key: "2", modifiers: [.control, .shift])
        case .processBWNegative: return WorkflowShortcut(key: "3", modifiers: [.control, .shift])
        case .processBWPositive: return WorkflowShortcut(key: "4", modifiers: [.control, .shift])
        case .targetMain: return WorkflowShortcut(key: "1", modifiers: [.control])
        case .targetPrint: return WorkflowShortcut(key: "2", modifiers: [.control])
        case .targetHS: return WorkflowShortcut(key: "3", modifiers: [.control])
        case .targetSP: return WorkflowShortcut(key: "4", modifiers: [.control])
        case .targetF135: return WorkflowShortcut(key: "5", modifiers: [.control])
        case .targetHR: return WorkflowShortcut(key: "6", modifiers: [.control])
        case .targetExpired: return WorkflowShortcut(key: "7", modifiers: [.control])
        case .cropTool: return WorkflowShortcut(key: "r", modifiers: [])
        case .basePickerTool: return WorkflowShortcut(key: "w", modifiers: [])
        case .autoDefectTool: return WorkflowShortcut(key: "q", modifiers: [.shift])
        case .guidedDefectTool: return WorkflowShortcut(key: "q", modifiers: [])
        case .brushDefectTool: return WorkflowShortcut(key: "b", modifiers: [])
        case .cloneStampTool: return WorkflowShortcut(key: "s", modifiers: [])
        case .rotateLeft: return WorkflowShortcut(key: "[", modifiers: [.command, .shift])
        case .rotateRight: return WorkflowShortcut(key: "]", modifiers: [.command, .shift])
        case .flipHorizontal: return WorkflowShortcut(key: "h", modifiers: [.command, .option])
        case .flipVertical: return WorkflowShortcut(key: "v", modifiers: [.command, .option])
        case .toggleBeforeAfter: return WorkflowShortcut(key: "\\", modifiers: [])
        case .showHideSidebar: return WorkflowShortcut(key: "1", modifiers: [.command, .option])
        case .showHideFilmstrip: return WorkflowShortcut(key: "2", modifiers: [.command, .option])
        case .showHideInspector: return WorkflowShortcut(key: "3", modifiers: [.command, .option])
        case .toggleFullScreen: return WorkflowShortcut(key: "f", modifiers: [.command, .control])
        case .openLibraryWorkspace: return WorkflowShortcut(key: "4", modifiers: [.command, .option])
        case .openDevelopWorkspace: return WorkflowShortcut(key: "5", modifiers: [.command, .option])
        case .openPrintWorkspace: return WorkflowShortcut(key: "6", modifiers: [.command, .option])
        case .detectScanners: return WorkflowShortcut(key: "d", modifiers: [.command, .shift])
        case .toggleScannerSimulator: return WorkflowShortcut(key: "d", modifiers: [.command, .option])
        case .previewScan: return WorkflowShortcut(key: "p", modifiers: [.command, .option])
        case .scanFrame: return WorkflowShortcut(key: "s", modifiers: [.command, .option])
        case .quickExport: return WorkflowShortcut(key: "e", modifiers: [.command])
        case .exportPhoto: return WorkflowShortcut(key: "e", modifiers: [.command, .shift])
        case .openHelp: return WorkflowShortcut(key: "h", modifiers: [.command, .shift])
        }
    }

    static func ratingAction(_ value: Int) -> WorkflowShortcutAction {
        switch value {
        case 1: return .rateOne
        case 2: return .rateTwo
        case 3: return .rateThree
        case 4: return .rateFour
        case 5: return .rateFive
        default: return .rateZero
        }
    }

    static func developmentProcessAction(_ filmType: FilmType) -> WorkflowShortcutAction {
        switch filmType {
        case .colorNegative: return .processColorNegative
        case .colorPositive: return .processColorPositive
        case .bwNegative: return .processBWNegative
        case .bwPositive: return .processBWPositive
        }
    }

    static func developTargetAction(_ target: DevelopTarget) -> WorkflowShortcutAction {
        switch target {
        case .main: return .targetMain
        case .print: return .targetPrint
        case .noritsu: return .targetHS
        case .sp3000: return .targetSP
        case .f135: return .targetF135
        case .hr: return .targetHR
        case .rescue: return .targetExpired
        }
    }

    @MainActor
    func title(in model: AppModel) -> String {
        switch self {
        case .importImages: return model.text(.commandImportImages)
        case .importFolder: return model.text(AppLocalizedPhrase.importFolder)
        case .refreshLibrary: return model.text(.commandRefreshLibrary)
        case .loadScanner: return model.text(.loadScanner)
        case .libraryGrid: return model.cullingText(.grid)
        case .libraryCompare: return model.cullingText(.compare)
        case .librarySurvey: return model.cullingText(.survey)
        case .previousPhoto: return model.text(AppLocalizedPhrase.previousFrame)
        case .nextPhoto: return model.text(AppLocalizedPhrase.nextFrame)
        case .pickPhoto: return model.text(.commandPick)
        case .clearPick: return model.text(AppLocalizedPhrase.clearPick)
        case .rejectPhoto: return model.text(.commandReject)
        case .deletePhoto: return model.text(.commandDeletePhoto)
        case .rateZero: return model.text(AppLocalizedPhrase.resetRating)
        case .rateOne: return model.text(AppLocalizedPhrase.starHelpFormat, 1)
        case .rateTwo: return model.text(AppLocalizedPhrase.starHelpFormat, 2)
        case .rateThree: return model.text(AppLocalizedPhrase.starHelpFormat, 3)
        case .rateFour: return model.text(AppLocalizedPhrase.starHelpFormat, 4)
        case .rateFive: return model.text(AppLocalizedPhrase.starHelpFormat, 5)
        case .createVirtualCopy: return model.text(AppLocalizedPhrase.virtualCopy)
        case .autoTone: return model.text(.commandAutoTone)
        case .autoWhiteBalance: return model.text(.commandAutoWhiteBalance)
        case .toggleAutoColor: return model.text(AppLocalizedPhrase.autoColor)
        case .toggleAutoLevels: return model.text(AppLocalizedPhrase.autoLevels)
        case .toggleNoiseReduction: return model.text(AppLocalizedPhrase.noiseReduction)
        case .resetAdjustments: return model.text(.commandResetAdjustments)
        case .copyDevelopSettings: return model.text(.commandCopyDevelopSettings)
        case .pasteDevelopSettings: return model.text(.commandPasteDevelopSettings)
        case .processColorNegative:
            return "\(model.text(AppLocalizedPhrase.process)): \(FilmType.colorNegative.developmentProcessName)"
        case .processColorPositive:
            return "\(model.text(AppLocalizedPhrase.process)): \(FilmType.colorPositive.developmentProcessName)"
        case .processBWNegative:
            return "\(model.text(AppLocalizedPhrase.process)): \(FilmType.bwNegative.developmentProcessName)"
        case .processBWPositive:
            return "\(model.text(AppLocalizedPhrase.process)): \(FilmType.bwPositive.developmentProcessName)"
        case .targetMain:
            return targetTitle(.main, in: model)
        case .targetPrint:
            return targetTitle(.print, in: model)
        case .targetHS:
            return targetTitle(.noritsu, in: model)
        case .targetSP:
            return targetTitle(.sp3000, in: model)
        case .targetF135:
            return targetTitle(.f135, in: model)
        case .targetHR:
            return targetTitle(.hr, in: model)
        case .targetExpired:
            return targetTitle(.rescue, in: model)
        case .cropTool: return model.text(AppLocalizedPhrase.cropArea)
        case .basePickerTool: return model.text(AppLocalizedPhrase.pickBase)
        case .autoDefectTool:
            return defectToolTitle(AppLocalizedPhrase.autoDefect, in: model)
        case .guidedDefectTool:
            return defectToolTitle(AppLocalizedPhrase.guidedDefect, in: model)
        case .brushDefectTool:
            return defectToolTitle(AppLocalizedPhrase.brushDefect, in: model)
        case .cloneStampTool:
            return defectToolTitle(AppLocalizedPhrase.cloneStamp, in: model)
        case .rotateLeft: return model.text(AppLocalizedPhrase.rotateLeft)
        case .rotateRight: return model.text(AppLocalizedPhrase.rotateRight)
        case .flipHorizontal: return model.text(AppLocalizedPhrase.flipHorizontal)
        case .flipVertical: return model.text(AppLocalizedPhrase.flipVertical)
        case .toggleBeforeAfter: return model.text(AppLocalizedPhrase.compareSplitVertical)
        case .showHideSidebar: return model.text(.commandShowHideSidebar)
        case .showHideFilmstrip: return model.text(.commandShowHideFilmstrip)
        case .showHideInspector: return model.text(.commandShowHideInspector)
        case .toggleFullScreen: return model.text(.commandToggleFullScreen)
        case .openLibraryWorkspace: return model.text(.menuLibrary)
        case .openDevelopWorkspace: return model.text(.menuDevelop)
        case .openPrintWorkspace: return model.text(.menuPrint)
        case .detectScanners: return model.text(.commandDetectScanners)
        case .toggleScannerSimulator: return model.text(.commandToggleScannerSimulator)
        case .previewScan: return model.text(.commandPreviewScan)
        case .scanFrame: return model.text(.commandScanFrame)
        case .quickExport: return model.text(.commandQuickExport)
        case .exportPhoto: return model.text(.commandExport)
        case .openHelp: return model.text(.commandNegaflowHelp)
        }
    }

    @MainActor
    private func targetTitle(_ target: DevelopTarget, in model: AppModel) -> String {
        "\(model.text(AppLocalizedPhrase.target)): \(target.displayName(language: model.appLanguage))"
    }

    @MainActor
    private func defectToolTitle(_ tool: AppLocalizedPhrase, in model: AppModel) -> String {
        "\(model.text(AppLocalizedPhrase.inspectorTabDefect)): \(model.text(tool))"
    }
}
