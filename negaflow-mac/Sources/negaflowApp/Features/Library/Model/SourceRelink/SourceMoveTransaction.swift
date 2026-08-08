import Foundation

struct SourceMoveFileOperations: @unchecked Sendable {
    let fileExists: @Sendable (URL) -> Bool
    let move: @Sendable (URL, URL) throws -> Void

    static let live = SourceMoveFileOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        move: { try FileManager.default.moveItem(at: $0, to: $1) }
    )
}

struct SourceMoveRollbackToken: Sendable {
    let completedMoves: [SourceMovePlan.FileMove]
}

enum SourceMoveFileOutcome: Sendable {
    case moved(SourceMoveRollbackToken)
    case sourceMissing
    case collision
    case failed(rollbackFailures: [String])
}

enum SourceMoveTransaction {
    static func move(
        _ moves: [SourceMovePlan.FileMove],
        operations: SourceMoveFileOperations = .live
    ) -> SourceMoveFileOutcome {
        guard !moves.isEmpty,
              moves.allSatisfy({ operations.fileExists($0.sourceURL) }) else {
            return .sourceMissing
        }
        guard moves.allSatisfy({ !operations.fileExists($0.destinationURL) }) else {
            return .collision
        }
        var completed: [SourceMovePlan.FileMove] = []
        for move in moves {
            do {
                try operations.move(move.sourceURL, move.destinationURL)
                completed.append(move)
            } catch {
                return .failed(rollbackFailures: rollback(completed, operations: operations))
            }
        }
        return .moved(SourceMoveRollbackToken(completedMoves: completed))
    }

    static func rollback(
        _ token: SourceMoveRollbackToken,
        operations: SourceMoveFileOperations = .live
    ) -> [String] {
        rollback(token.completedMoves, operations: operations)
    }

    private static func rollback(
        _ moves: [SourceMovePlan.FileMove],
        operations: SourceMoveFileOperations
    ) -> [String] {
        var failures: [String] = []
        for move in moves.reversed() {
            do {
                try operations.move(move.destinationURL, move.sourceURL)
                if !operations.fileExists(move.sourceURL) {
                    failures.append(move.sourceURL.path)
                }
            } catch {
                failures.append(move.sourceURL.path)
            }
        }
        return failures.sorted()
    }
}
