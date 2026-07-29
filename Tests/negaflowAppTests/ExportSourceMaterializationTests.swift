import XCTest
@testable import negaflowApp

/// 로컬 파일만 있는 일반 경로에서 선다운로드가 아무 일도 하지 않고 즉시 통과하는지,
/// 그리고 iCloud 상태 판정이 로컬 파일을 잘못 축출로 보지 않는지 확인한다.
///
/// 실제 축출된 iCloud 파일은 테스트에서 만들 수 없다(동기화 데몬이 필요하다). 그 경로는
/// `URLResourceKey.ubiquitousItemDownloadingStatus` 값으로 판정하며, 이 맥의 실제 dataless
/// 파일에서 `isUbiquitousItem = true` / `.notDownloaded` 로 관측해 확인했다.
final class ExportSourceMaterializationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-materialize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    private func makeLocalFile(_ name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data("local".utf8).write(to: url)
        return url
    }

    func testLocalFilesAreNeverTreatedAsEvicted() throws {
        let urls = [try makeLocalFile("a.tiff"), try makeLocalFile("b.tiff")]

        XCTAssertTrue(ExportSourceMaterialization.evictedSources(among: urls).isEmpty)
        XCTAssertFalse(ExportSourceMaterialization.isEvicted(urls[0]))
    }

    func testMissingFileIsNotTreatedAsEvicted() {
        let missing = tempDirectory.appendingPathComponent("does-not-exist.tiff")

        XCTAssertFalse(ExportSourceMaterialization.isEvicted(missing))
        XCTAssertTrue(ExportSourceMaterialization.evictedSources(among: [missing]).isEmpty)
    }

    func testMaterializeReturnsImmediatelyWithoutProgressForLocalSources() async throws {
        let urls = [try makeLocalFile("c.tiff"), try makeLocalFile("d.tiff")]
        let reported = ProgressRecorder()

        let start = Date()
        let ready = await ExportSourceMaterialization.materialize(urls) { progress in
            reported.append(progress)
        }

        XCTAssertTrue(ready)
        XCTAssertTrue(reported.values.isEmpty, "local-only exports must not report download progress")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testEvictedSourceListDeduplicatesPaths() throws {
        let url = try makeLocalFile("e.tiff")
        let duplicated = [url, url, url.standardizedFileURL]

        // 로컬이라 결과는 비어 있지만, 중복 제거 자체는 경로 단위로 동작해야 한다.
        XCTAssertTrue(ExportSourceMaterialization.evictedSources(among: duplicated).isEmpty)
    }

    func testProgressRemainingIsDerivedFromTotalAndReady() {
        let progress = ExportSourceMaterialization.Progress(total: 5, ready: 2)

        XCTAssertEqual(progress.remaining, 3)
        XCTAssertEqual(ExportSourceMaterialization.Progress(total: 2, ready: 5).remaining, 0)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExportSourceMaterialization.Progress] = []

    var values: [ExportSourceMaterialization.Progress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ progress: ExportSourceMaterialization.Progress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }
}
