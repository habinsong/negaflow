import Combine
import Foundation
import SwiftUI
import AppKit

extension AppModel {
    var workflowShortcutActions: [WorkflowShortcutAction] {
        WorkflowShortcutAction.allCases
    }

    func shortcut(for action: WorkflowShortcutAction) -> WorkflowShortcut {
        workflowShortcutStore.shortcut(for: action)
    }

    @discardableResult
    func setShortcut(_ shortcut: WorkflowShortcut, for action: WorkflowShortcutAction) -> Bool {
        workflowShortcutStore.setShortcut(shortcut, for: action)
    }

    func resetWorkflowShortcut(for action: WorkflowShortcutAction) {
        workflowShortcutStore.resetShortcut(for: action)
    }

    func resetAllWorkflowShortcuts() {
        workflowShortcutStore.resetAll()
    }

    func canPerformWorkflowShortcutAction(_ action: WorkflowShortcutAction) -> Bool {
        switch action {
        case .importImages, .importFolder, .refreshLibrary, .loadScanner,
             .libraryGrid, .libraryCompare, .librarySurvey,
             .showHideSidebar, .showHideFilmstrip, .showHideInspector, .toggleScannerSimulator,
             .toggleFullScreen, .openLibraryWorkspace, .openDevelopWorkspace, .openPrintWorkspace,
             .processColorNegative, .processColorPositive, .processBWNegative, .processBWPositive,
             .targetMain, .targetPrint, .targetHS, .targetSP, .targetF135, .targetHR, .targetExpired,
             .openHelp:
            return true
        case .previousPhoto:
            guard let id = actionableFrame?.id,
                  let index = interactionFrameIDs.firstIndex(of: id) else { return false }
            return index > 0
        case .nextPhoto:
            guard let id = actionableFrame?.id,
                  let index = interactionFrameIDs.firstIndex(of: id) else { return false }
            return index < interactionFrameIDs.count - 1
        case .pickPhoto, .clearPick, .rejectPhoto, .deletePhoto, .rateZero, .rateOne, .rateTwo,
             .rateThree, .rateFour, .rateFive, .createVirtualCopy, .toggleBeforeAfter:
            return actionableFrame != nil
        case .autoTone, .autoWhiteBalance, .toggleNoiseReduction, .resetAdjustments,
             .copyDevelopSettings, .cropTool, .autoDefectTool, .guidedDefectTool,
             .brushDefectTool, .cloneStampTool, .rotateLeft, .rotateRight,
             .flipHorizontal, .flipVertical:
            return actionableFrame != nil
        case .toggleAutoColor, .toggleAutoLevels, .basePickerTool:
            return actionableFrame?.filmType.requiresInversion == true
        case .pasteDevelopSettings:
            return actionableFrame != nil && copiedDevelopSettings != nil
        case .detectScanners:
            return !isDetecting && !isScanning
        case .previewScan:
            return canPreview
        case .scanFrame:
            return canScan
        case .quickExport, .exportPhoto:
            return canExportSelection
        }
    }

    func performWorkflowShortcutAction(_ action: WorkflowShortcutAction) {
        guard canPerformWorkflowShortcutAction(action) else { return }

        switch action {
        case .importImages:
            presentImportPanel()
        case .importFolder:
            presentImportFolderPanel()
        case .refreshLibrary:
            refreshLibrary()
        case .libraryGrid:
            libraryCullingMode = .grid
            activeWorkspaceModule = .library
        case .libraryCompare:
            libraryCullingMode = .compare
            activeWorkspaceModule = .library
        case .librarySurvey:
            libraryCullingMode = .survey
            activeWorkspaceModule = .library
        case .detectScanners:
            presentScannerSetup()
            Task { await refreshDevices() }
        case .loadScanner:
            presentScannerSetup()
        case .previousPhoto:
            selectAdjacentFrame(-1)
        case .nextPhoto:
            selectAdjacentFrame(1)
        case .pickPhoto:
            actionableFrame?.pickState = .picked
        case .clearPick:
            actionableFrame?.pickState = .unflagged
        case .rejectPhoto:
            actionableFrame?.pickState = .rejected
        case .deletePhoto:
            if let frame = actionableFrame { deleteFrame(frame) }
        case .rateZero:
            actionableFrame?.setRating(0)
        case .rateOne:
            actionableFrame?.toggleRating(1)
        case .rateTwo:
            actionableFrame?.toggleRating(2)
        case .rateThree:
            actionableFrame?.toggleRating(3)
        case .rateFour:
            actionableFrame?.toggleRating(4)
        case .rateFive:
            actionableFrame?.toggleRating(5)
        case .createVirtualCopy:
            if let frame = actionableFrame { createVirtualCopy(from: frame) }
        case .autoTone:
            if let frame = actionableFrame { autoTone(frame) }
        case .autoWhiteBalance:
            if let frame = actionableFrame { autoWhiteBalance(frame) }
        case .toggleAutoColor:
            if let frame = actionableFrame {
                frame.updateParams { $0.autoNeutralBalance.toggle() }
                requestDevelop(frame)
            }
        case .toggleAutoLevels:
            if let frame = actionableFrame {
                frame.updateParams { $0.autoLevels.toggle() }
                requestDevelop(frame)
            }
        case .toggleNoiseReduction:
            if let frame = actionableFrame {
                frame.updateParams {
                    $0.noiseReduction = $0.noiseReduction > 1e-3 ? 0 : 0.7
                }
                requestDevelop(frame)
            }
        case .resetAdjustments:
            if let frame = actionableFrame {
                DevelopInspectorResetter.resetAllAdjustments(frame: frame, neutralPreset: nil)
                Task { await developFrame(frame) }
            }
        case .copyDevelopSettings:
            if let frame = actionableFrame { copyDevelopSettings(from: frame) }
        case .pasteDevelopSettings:
            if let frame = actionableFrame { pasteDevelopSettings(to: frame) }
        case .processColorNegative:
            applyDevelopmentProcess(.colorNegative, to: actionableFrame)
        case .processColorPositive:
            applyDevelopmentProcess(.colorPositive, to: actionableFrame)
        case .processBWNegative:
            applyDevelopmentProcess(.bwNegative, to: actionableFrame)
        case .processBWPositive:
            applyDevelopmentProcess(.bwPositive, to: actionableFrame)
        case .targetMain:
            applyDevelopTarget(.main, to: actionableFrame)
        case .targetPrint:
            applyDevelopTarget(.print, to: actionableFrame)
        case .targetHS:
            applyDevelopTarget(.noritsu, to: actionableFrame)
        case .targetSP:
            applyDevelopTarget(.sp3000, to: actionableFrame)
        case .targetF135:
            applyDevelopTarget(.f135, to: actionableFrame)
        case .targetHR:
            applyDevelopTarget(.hr, to: actionableFrame)
        case .targetExpired:
            applyDevelopTarget(.rescue, to: actionableFrame)
        case .cropTool, .basePickerTool, .autoDefectTool, .guidedDefectTool,
             .brushDefectTool, .cloneStampTool:
            activeWorkspaceModule = .develop
            pendingDevelopToolShortcutAction = action
            developToolShortcutRequest &+= 1
        case .rotateLeft:
            if let frame = actionableFrame { rotate(frame, clockwise: false) }
        case .rotateRight:
            if let frame = actionableFrame { rotate(frame, clockwise: true) }
        case .flipHorizontal:
            if let frame = actionableFrame { flipHorizontally(frame) }
        case .flipVertical:
            if let frame = actionableFrame { flipVertically(frame) }
        case .toggleBeforeAfter:
            beforeAfterToggleRequest += 1
        case .showHideSidebar, .showHideFilmstrip, .showHideInspector:
            break
        case .openLibraryWorkspace:
            activeWorkspaceModule = .library
        case .openDevelopWorkspace:
            activeWorkspaceModule = .develop
        case .openPrintWorkspace:
            activeWorkspaceModule = .print
        case .toggleFullScreen:
            NSApp.keyWindow?.toggleFullScreen(nil)
        case .toggleScannerSimulator:
            toggleDemo(!demoMode)
        case .previewScan:
            Task { await runScan(preview: true) }
        case .scanFrame:
            Task { await scanFrames(count: 1, preview: false) }
        case .quickExport:
            quickExportSelection(for: activeWorkspaceModule)
        case .exportPhoto:
            exportSelectionToFolder(for: activeWorkspaceModule)
        case .openHelp:
            break
        }
    }

    private func selectAdjacentFrame(_ offset: Int) {
        let orderedFrameIDs = interactionFrameIDs
        guard let id = actionableFrame?.id,
              let index = orderedFrameIDs.firstIndex(of: id) else { return }
        let nextIndex = min(max(index + offset, 0), orderedFrameIDs.count - 1)
        guard orderedFrameIDs.indices.contains(nextIndex),
              let frame = frames.first(where: { $0.id == orderedFrameIDs[nextIndex] }) else {
            return
        }
        selectFrame(frame, orderedFrameIDs: orderedFrameIDs, modifiers: [])
    }
}
