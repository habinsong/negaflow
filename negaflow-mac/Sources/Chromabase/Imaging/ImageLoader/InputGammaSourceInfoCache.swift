import Foundation

enum InputGammaSourceInfoCache {
    private struct Key: Hashable {
        let url: URL
        let observation: InputGammaFileObservation
    }
    private final class Store: @unchecked Sendable {
        let condition = NSCondition()
        var values: [Key: InputGammaSourceInfo] = [:]
        var pending: Set<Key> = []
    }
    private static let store = Store()

    static func read(_ url: URL, inspect: () throws -> InputGammaSourceInfo) throws -> InputGammaSourceInfo {
        let key = Key(url: url.standardizedFileURL, observation: try InputGammaFileObservation.read(url))
        store.condition.lock()
        while store.pending.contains(key) { store.condition.wait() }
        if let value = store.values[key] {
            store.condition.unlock()
            guard try InputGammaFileObservation.read(url) == key.observation else {
                throw InputGammaDecodeError.decodeFailed
            }
            return value
        }
        store.pending.insert(key)
        store.condition.unlock()
        // 서로 다른 파일의 ICC/추정 작업은 독립적으로 진행합니다.
        let result = Result {
            let value = try inspect()
            guard try InputGammaFileObservation.read(url) == key.observation else {
                throw InputGammaDecodeError.decodeFailed
            }
            return value
        }
        store.condition.lock()
        if case .success(let value) = result {
            if store.values.count >= 64 { store.values.removeAll(keepingCapacity: true) }
            store.values[key] = value
        }
        store.pending.remove(key)
        store.condition.broadcast()
        store.condition.unlock()
        return try result.get()
    }
}
