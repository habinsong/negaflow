import Foundation
import Chromabase

// 사진 한 장의 부수 값이 이 빌드가 모르는 형식이어도 그 사진을 잃지 않는다.
//
// 되돌리는 대상은 **사진의 정체와 무관한 값**뿐이다 — 깃발, 표시 이름, 시각, 편집 이력.
// 필름 종류·현상 파라미터·변형·원본 경로는 그대로 엄격하게 읽는다. 그것들을 임의로
// 되돌리면 사진을 살리는 것이 아니라 다른 사진으로 바꾸는 것이 된다.
//
// 사진을 건너뛰지 않고 값만 되돌리는 이유: macOS 는 프레임을 강타입으로 읽으므로 한 장을
// 건너뛰면 다음 저장에서 그 사진이 카탈로그에서 사라진다. 되돌리면 남는다.

// 아래 셋은 반드시 `singleValueContainer()` 를 거쳐 읽는다. `Date(from:)` 처럼 타입의
// Decodable 을 직접 부르면 JSONDecoder 의 `dateDecodingStrategy`(.iso8601) 를 건너뛰어
// 멀쩡한 값까지 못 읽는다.

/// 이 빌드가 모르는 깃발 값은 "표시 없음" 으로 읽는다. 사용자가 다시 지정할 수 있다.
struct LenientPickState: Decodable, Equatable, Sendable {
    var value: FramePickState

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = (try? container.decode(FramePickState.self)) ?? .unflagged
    }
}

/// 읽을 수 없는 시각은 아주 옛날로 둔다. 정렬에서 맨 끝에 모이므로 눈에 띄고, 사용자가
/// 사진을 잃는 것보다 낫다. 값을 그럴듯하게 지어내지는 않는다.
struct LenientScanDate: Decodable, Equatable, Sendable {
    var value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = (try? container.decode(Date.self)) ?? .distantPast
    }
}

/// 표시 이름이 문자열이 아니면 버린다. 이름이 없으면 파일 이름으로 보여 주면 된다.
struct LenientDisplayName: Decodable, Equatable, Sendable {
    var value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(String.self)
    }
}

/// 편집 이력은 한 줄이 낯설면 그 줄만 버린다. 지금 현상값은 `params` 에 따로 있으므로
/// 이력이 조금 짧아져도 사진이 달라지지 않는다.
struct LenientArray<Element: Decodable & Sendable>: Decodable, Sendable {
    var values: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            // 실패한 원소에서 커서가 멈추지 않도록 원소마다 이 래퍼로 한 번 감싸 읽는다.
            let element = try container.decode(SkippedIfUnreadable<Element>.self)
            if let value = element.value {
                decoded.append(value)
            }
        }
        values = decoded
    }
}

private struct SkippedIfUnreadable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
