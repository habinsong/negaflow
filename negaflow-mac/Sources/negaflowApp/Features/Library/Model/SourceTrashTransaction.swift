import Foundation

/// Transaction은 호출 스레드에서만 closure를 순차 실행한다. immutable operation bundle 자체만
/// 작업 경계를 통과할 수 있게 표시하고, 내부 FileManager 호출은 각 closure 안에서 수행한다.
struct SourceTrashFileOperations: @unchecked Sendable {
    let fileExists: (URL) -> Bool
    let moveToTrash: (URL) throws -> URL
    let restoreFromTrash: (URL, URL) throws -> Void

    static let live = SourceTrashFileOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        moveToTrash: { originalURL in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: originalURL,
                resultingItemURL: &resultingURL
            )
            guard let resultingURL else {
                throw SourceTrashFileOperationError.missingResultingURL
            }
            return resultingURL as URL
        },
        restoreFromTrash: { trashedURL, originalURL in
            try FileManager.default.moveItem(at: trashedURL, to: originalURL)
        }
    )
}

private enum SourceTrashFileOperationError: Error {
    case missingResultingURL
}

enum SourceTrashTransactionOutcome: Equatable {
    case committed
    case missingFiles([String])
    case moveFailed(path: String, rollbackFailures: [String])
    case catalogCommitFailed(rollbackFailures: [String])
}

enum SourceTrashTransaction {
    struct MoveRecord: Sendable {
        let originalURL: URL
        let trashedURL: URL
    }

    /// stage 결과: 이동 완료(커밋 대기) 또는 자체 롤백까지 끝난 실패.
    enum StageOutcome: Sendable {
        case staged([MoveRecord])
        case missingFiles([String])
        case moveFailed(path: String, rollbackFailures: [String])
    }

    /// 존재 검사 + 휴지통 이동까지 수행한다(카탈로그 커밋 전 단계). 이동 도중 실패하면 이미
    /// 옮긴 파일을 역순으로 원위치한 뒤 실패를 돌려준다. 호출 스레드에서 순차 실행 —
    /// 백그라운드 실행은 호출측(performSourceDeletion)이 담당한다.
    static func stage(
        urls: [URL],
        operations: SourceTrashFileOperations
    ) -> StageOutcome {
        let uniqueURLs = Dictionary(grouping: urls.map(\.standardizedFileURL)) {
            $0.path
        }
        .keys
        .sorted()
        .map { URL(fileURLWithPath: $0) }
        let missing = uniqueURLs.filter { !operations.fileExists($0) }.map(\.path)
        guard missing.isEmpty else { return .missingFiles(missing) }

        var moved: [MoveRecord] = []
        for originalURL in uniqueURLs {
            do {
                let trashedURL = try operations.moveToTrash(originalURL)
                moved.append(MoveRecord(
                    originalURL: originalURL,
                    trashedURL: trashedURL
                ))
            } catch {
                var rollbackFailures = rollback(moved, operations: operations)
                // live trash API가 이동에는 성공했지만 resulting URL을 돌려주지 않는 등,
                // 실패가 원본 경로를 이미 비운 뒤 발생하면 복구 불가 상태를 숨기지 않는다.
                if !operations.fileExists(originalURL) {
                    rollbackFailures.append(originalURL.path)
                    rollbackFailures = Array(Set(rollbackFailures)).sorted()
                }
                return .moveFailed(
                    path: originalURL.path,
                    rollbackFailures: rollbackFailures
                )
            }
        }
        return .staged(moved)
    }

    static func perform(
        urls: [URL],
        operations: SourceTrashFileOperations,
        commitCatalog: () -> Bool
    ) -> SourceTrashTransactionOutcome {
        switch stage(urls: urls, operations: operations) {
        case .missingFiles(let missing):
            return .missingFiles(missing)
        case .moveFailed(let path, let rollbackFailures):
            return .moveFailed(path: path, rollbackFailures: rollbackFailures)
        case .staged(let moved):
            guard commitCatalog() else {
                return .catalogCommitFailed(
                    rollbackFailures: rollback(moved, operations: operations)
                )
            }
            return .committed
        }
    }

    static func rollback(
        _ moved: [MoveRecord],
        operations: SourceTrashFileOperations
    ) -> [String] {
        var failures: [String] = []
        for record in moved.reversed() {
            do {
                try operations.restoreFromTrash(
                    record.trashedURL,
                    record.originalURL
                )
                if !operations.fileExists(record.originalURL) {
                    failures.append(record.originalURL.path)
                }
            } catch {
                failures.append(record.originalURL.path)
            }
        }
        return failures.sorted()
    }
}
