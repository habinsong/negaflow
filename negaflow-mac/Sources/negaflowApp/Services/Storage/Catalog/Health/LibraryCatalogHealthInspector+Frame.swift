import Foundation
import ScannerKit
import Chromabase

extension LibraryCatalogHealthInspector {
    static func inspectFrame(
        _ frame: LibraryFrameRecord,
        frameIndex: Int,
        allFrameIDs: Set<UUID>,
        defectDirectory: URL,
        cleanedRawDirectory: URL,
        fileManager: FileManager,
        includeWarnings: Bool,
        issues: inout [LibraryCatalogHealthIssue]
    ) {
        let rawPath = frame.rawScanPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawPath.isEmpty {
            issues.append(issue(.emptySourcePath, .error, frameID: frame.id, frameIndex: frameIndex))
        } else if includeWarnings {
            let location = SourceBookmark.resolve(
                frame.rawScanBookmarkData,
                fallbackURL: URL(fileURLWithPath: frame.rawScanPath),
                fileManager: fileManager
            )
            if !fileManager.fileExists(atPath: location.url.path) {
                issues.append(issue(.offlineSource, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
        }

        if includeWarnings, let infraredPath = frame.infraredScanPath {
            let location = SourceBookmark.resolve(
                frame.infraredScanBookmarkData,
                fallbackURL: URL(fileURLWithPath: infraredPath),
                fileManager: fileManager
            )
            if !fileManager.fileExists(atPath: location.url.path) {
                issues.append(issue(.offlineInfraredSource, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
        }
        if FrameSource(storageKey: frame.sourceKind) == nil {
            issues.append(issue(.unsupportedSourceKind, .error, frameID: frame.id, frameIndex: frameIndex))
        }
        if !(0...5).contains(frame.rating) {
            issues.append(issue(.invalidRating, .error, frameID: frame.id, frameIndex: frameIndex))
        }
        if includeWarnings {
            if let baseRGB = frame.baseRGB, baseRGB.count != 3 {
                issues.append(issue(.invalidBaseRGB, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if frame.scanIndex <= 0 {
                issues.append(issue(.invalidScanIndex, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if let width = frame.sourcePixelWidth, width <= 0 {
                issues.append(issue(.invalidPixelDimensions, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if let height = frame.sourcePixelHeight, height <= 0 {
                issues.append(issue(.invalidPixelDimensions, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if let dpi = frame.sourceResolutionDPI, dpi <= 0 {
                issues.append(issue(.invalidResolution, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if let depth = frame.sourceBitDepth, depth <= 0 {
                issues.append(issue(.invalidBitDepth, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
        }
        if let metadata = frame.sourceMetadata {
            inspectSourceMetadata(
                metadata,
                frame: frame,
                frameIndex: frameIndex,
                issues: &issues
            )
        }
        if let overlay = frame.appMetadataOverlay, !overlay.isValid {
            issues.append(issue(
                .invalidAppMetadataOverlay,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
        }

        if includeWarnings {
            if frame.sourceFrameID == frame.id {
                issues.append(issue(.selfReferentialVirtualCopy, .warning, frameID: frame.id, frameIndex: frameIndex))
            } else if let sourceFrameID = frame.sourceFrameID, !allFrameIDs.contains(sourceFrameID) {
                issues.append(issue(.missingVirtualCopySource, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
            if (frame.sourceFrameID == nil) != (frame.virtualCopyNumber == nil) {
                issues.append(issue(.inconsistentVirtualCopy, .warning, frameID: frame.id, frameIndex: frameIndex))
            }
        }

        // 결함 기록/캐시는 세션 전용이다(종료 시 이미지에 굽고 기록은 폐기). legacy catalog의
        // hasDefectEdits/cleanedRawPath는 검사하지 않는다 — 잔재 파일이 없어도 열기를 막지 않는다.
    }


}
