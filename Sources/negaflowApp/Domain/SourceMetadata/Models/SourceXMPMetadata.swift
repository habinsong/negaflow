import Foundation

struct SourceXMPMetadata: Codable, Equatable, Sendable {
    var createDateRaw: String?
    var dateCreatedRaw: String?
    var title: SourceLocalizedText?
    var description: SourceLocalizedText?
    var creators: [String]
    var rights: SourceLocalizedText?
    var usageTerms: SourceLocalizedText?
    var headline: String?
    var credit: String?
    var jobIdentifier: String?
    var keywords: [String]
    var city: String?
    var stateProvince: String?
    var country: String?
    var sublocation: String?
    /// IPTC/XMP 계약의 -1 또는 0...5 Decimal을 원형 그대로 보존한다.
    var rating: Double?
    var label: String?

    /// 디지털 표현 생성 시각. 콘텐츠 생성 시각인 `dateCreated`와 의미가 다르다.
    var createDate: Date? { SourceMetadataReader.parseXMPDate(createDateRaw) }
    var dateCreated: Date? { SourceMetadataReader.parseXMPDate(dateCreatedRaw) }

    var isEmpty: Bool {
        createDateRaw == nil
            && dateCreatedRaw == nil
            && title == nil
            && description == nil
            && creators.isEmpty
            && rights == nil
            && usageTerms == nil
            && headline == nil
            && credit == nil
            && jobIdentifier == nil
            && keywords.isEmpty
            && city == nil
            && stateProvince == nil
            && country == nil
            && sublocation == nil
            && rating == nil
            && label == nil
    }
}

struct SourceLocalizedText: Codable, Equatable, Sendable {
    var valuesByLanguage: [String: String]

    var defaultValue: String? {
        valuesByLanguage["x-default"]
    }
}

enum SourceXMPReadState: String, Codable, Equatable, Sendable {
    case notFound
    case loaded
    case invalid
    case tooLarge
    case ambiguous
}

/// 원본에 기록된 현지 시각 구성요소다. timezone이 없을 때도 임의의 지역 timezone을
/// 대입하지 않고 원문 의미와 정렬 순서를 보존한다.
