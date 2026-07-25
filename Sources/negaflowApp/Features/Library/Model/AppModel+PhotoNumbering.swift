import Foundation

@MainActor
extension AppModel {
    func isPhotoNumberAvailable(_ number: Int, for frame: ScanFrame) -> Bool {
        guard number > 0, ownsFrame(frame) else { return false }
        let sourcePath = frame.rawScanURL.standardizedFileURL.path
        let folder = LibraryPresentation.folderURL(for: frame)
        return !frames.contains { candidate in
            candidate.rawScanURL.standardizedFileURL.path != sourcePath
                && LibraryPresentation.folderURL(for: candidate) == folder
                && candidate.presentationIndex == number
        }
    }

    @discardableResult
    func renamePhotoNumber(_ number: Int, for frame: ScanFrame) -> Bool {
        guard isPhotoNumberAvailable(number, for: frame) else { return false }
        let sourcePath = frame.rawScanURL.standardizedFileURL.path
        for candidate in frames
            where candidate.rawScanURL.standardizedFileURL.path == sourcePath {
            candidate.assignPhotoNumber(number)
        }
        return true
    }

    func movedPhotoNumberAssignments(for plan: SourceMovePlan) -> [String: Int] {
        guard plan.relinkPlan.oldFolderURL == nil,
              plan.relinkPlan.newFolderURL == nil else {
            return [:]
        }
        let movingSourcePaths = Set(plan.relinkPlan.mappings.map {
            $0.oldSourceURL.standardizedFileURL.path
        })
        var nextNumberByDestinationFolder: [String: Int] = [:]
        var assignments: [String: Int] = [:]

        for mapping in plan.relinkPlan.mappings {
            let sourcePath = mapping.oldSourceURL.standardizedFileURL.path
            let destinationFolder = mapping.newSourceURL
                .deletingLastPathComponent()
                .standardizedFileURL
            let destinationPath = destinationFolder.path
            let nextNumber = nextNumberByDestinationFolder[destinationPath] ?? {
                let highestExistingNumber = frames.lazy
                    .filter {
                        !movingSourcePaths.contains($0.rawScanURL.standardizedFileURL.path)
                            && LibraryPresentation.folderURL(for: $0) == destinationFolder
                    }
                    .map(\.presentationIndex)
                    .max() ?? 0
                return highestExistingNumber + 1
            }()
            assignments[sourcePath] = nextNumber
            nextNumberByDestinationFolder[destinationPath] = nextNumber + 1
        }
        return assignments
    }

    func applyMovedPhotoNumberAssignments(
        _ assignments: [String: Int]
    ) -> [(frame: ScanFrame, customDisplayName: String?)] {
        guard !assignments.isEmpty else { return [] }
        var snapshots: [(frame: ScanFrame, customDisplayName: String?)] = []
        for frame in frames {
            let sourcePath = frame.rawScanURL.standardizedFileURL.path
            guard let number = assignments[sourcePath] else { continue }
            snapshots.append((frame, frame.customDisplayName))
            frame.assignPhotoNumber(number)
        }
        return snapshots
    }

    func restorePhotoNumberAssignments(
        _ snapshots: [(frame: ScanFrame, customDisplayName: String?)]
    ) {
        for snapshot in snapshots {
            snapshot.frame.customDisplayName = snapshot.customDisplayName
        }
    }
}
