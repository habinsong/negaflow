import Foundation

extension ScanFrame: Hashable {
    nonisolated static func == (lhs: ScanFrame, rhs: ScanFrame) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
