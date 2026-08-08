import Foundation

struct SourceIPTCMetadata: Codable, Equatable, Sendable {
    var title: String?
    var headline: String?
    var caption: String?
    var creators: [String]
    var credit: String?
    var copyrightNotice: String?
    var rightsUsageTerms: String?
    var source: String?
    var jobIdentifier: String?
    var keywords: [String]
    var city: String?
    var stateProvince: String?
    var country: String?
    var countryCode: String?
    var sublocation: String?

    var isEmpty: Bool {
        title == nil
            && headline == nil
            && caption == nil
            && creators.isEmpty
            && credit == nil
            && copyrightNotice == nil
            && rightsUsageTerms == nil
            && source == nil
            && jobIdentifier == nil
            && keywords.isEmpty
            && city == nil
            && stateProvince == nil
            && country == nil
            && countryCode == nil
            && sublocation == nil
    }
}
