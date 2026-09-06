import Foundation
import Chromabase

/// 스크럽으로 되돌아온 감마의 작은 통계만 재사용합니다. 이미지 버퍼는 저장하지 않습니다.
struct InputGammaPreviewMeasurements {
    struct Key: Equatable {
        let source: ObjectIdentifier
        let sourceRevision: UInt64
        let rawRevision: Int
        let params: DevelopParameters
        let filmType: FilmType
        let preset: LookPreset?
        let dimension: CGFloat
    }
    struct Value {
        let base: FilmBase?
        let measurements: DevelopSceneMeasurements
    }
    private var entries: [(Key, Value)] = []

    mutating func value(for key: Key) -> Value? {
        guard let index = entries.firstIndex(where: { $0.0 == key }) else { return nil }
        let found = entries.remove(at: index)
        entries.append(found)
        return found.1
    }

    mutating func store(_ value: Value, for key: Key) {
        entries.removeAll { $0.0 == key }
        entries.append((key, value))
        if entries.count > 40 { entries.removeFirst(entries.count - 40) }
    }

    mutating func clear() { entries.removeAll() }
    var count: Int { entries.count }
}
