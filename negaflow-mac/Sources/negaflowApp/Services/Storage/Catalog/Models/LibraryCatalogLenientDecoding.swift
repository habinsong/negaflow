import Foundation

/// 목록의 원소 하나가 이 앱이 모르는 형식이어도 그 원소만 버리고 나머지를 읽는다.
///
/// 배열 전체를 이 래퍼로 디코드하기 때문에 실패한 원소에서 커서가 멈추지 않는다.
private struct SkippableElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// 키 자체는 필수다 — 키가 없는 것은 "빈 목록" 이 아니라 잘린 카탈로그라서,
    /// 조용히 빈 값으로 열면 다음 저장에서 사용자 정보가 지워진다.
    func decodeSkippingUnreadableElements<Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key
    ) throws -> [Value] {
        try decode([SkippableElement<Value>].self, forKey: key).compactMap(\.value)
    }
}
