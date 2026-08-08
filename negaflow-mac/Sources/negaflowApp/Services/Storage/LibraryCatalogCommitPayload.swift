import Foundation

/// MainActor에서 만든 immutable catalog snapshot을 utility task로 넘기는 명시적 경계다.
/// payload 생성 뒤에는 catalog를 수정하지 않고, background commit은 복사된 value만 읽는다.
struct LibraryCatalogCommitPayload: @unchecked Sendable {
    let catalog: LibraryCatalog
    let catalogURL: URL
    let defectDirectory: URL
}
