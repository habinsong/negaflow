import Foundation

final class DefectContrastAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var magnitude: [Float]
    private var thinMagnitude: [Float]

    init(count: Int) {
        magnitude = [Float](repeating: 0, count: count)
        thinMagnitude = [Float](repeating: 0, count: count)
    }

    func merge(_ local: [Float], includeInThin: Bool) {
        lock.lock()
        for index in local.indices {
            if local[index] > magnitude[index] { magnitude[index] = local[index] }
            if includeInThin, local[index] > thinMagnitude[index] {
                thinMagnitude[index] = local[index]
            }
        }
        lock.unlock()
    }

    func snapshot() -> (magnitude: [Float], thinMagnitude: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        return (magnitude, thinMagnitude)
    }
}

final class DefectScratchMapAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var best: [Float]
    private var bestPerpendicular: [Float]
    private var localRidge: [Float]

    init(count: Int) {
        best = [Float](repeating: 0, count: count)
        bestPerpendicular = [Float](repeating: 0, count: count)
        localRidge = [Float](repeating: 0, count: count)
    }

    func mergeBest(ridge: [Float], integrated: [Float]) {
        lock.lock()
        for index in ridge.indices {
            if ridge[index] > localRidge[index] { localRidge[index] = ridge[index] }
            if integrated[index] > best[index] { best[index] = integrated[index] }
        }
        lock.unlock()
    }

    func mergePerpendicular(_ integrated: [Float]) {
        lock.lock()
        for index in integrated.indices where integrated[index] > bestPerpendicular[index] {
            bestPerpendicular[index] = integrated[index]
        }
        lock.unlock()
    }

    func snapshot() -> (best: [Float], bestPerpendicular: [Float], localRidge: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        return (best, bestPerpendicular, localRidge)
    }
}
