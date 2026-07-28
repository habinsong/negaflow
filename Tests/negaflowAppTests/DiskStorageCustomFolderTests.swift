import Foundation
import XCTest
@testable import negaflowApp

/// 디스크 탭의 계약: 명시적으로 고른 폴더는 언제나 그 폴더를 쓰고, 위치 모드는 경로를 지정하지
/// 않은 폴더가 파생될 루트만 정한다.
///
/// 예전에는 `.custom` 모드에서만 지정 경로를 적용했다. 그래서 iCloud·데스크탑·특정 폴더 모드에서
/// 내보내기 폴더로 외장 디스크를 고르면 경로는 저장되지만 무시되고, 파일은 조용히 내부 루트로
/// 나갔다. 사용자에게는 "외장에는 저장이 안 된다"로 보인다.
@MainActor
final class DiskStorageCustomFolderTests: XCTestCase {

    private func makeStore() -> DiskStorageStore {
        let defaults = UserDefaults(suiteName: "negaflow.disk.\(UUID().uuidString)")!
        addTeardownBlock { defaults.removePersistentDomain(forName: defaults.description) }
        return DiskStorageStore(defaults: defaults)
    }

    /// 어떤 위치 모드에서도 지정한 내보내기 폴더가 그대로 쓰여야 한다.
    func testChosenExportFoldersAreUsedInEveryLocationMode() {
        for mode in DiskStorageLocationMode.allCases {
            let store = makeStore()
            store.locationMode = mode
            store.exportPath = "/Volumes/External/negaflow-export"
            store.quickExportPath = "/Volumes/External/negaflow-quick"

            XCTAssertEqual(
                store.exportURL.path,
                "/Volumes/External/negaflow-export",
                "\(mode)에서 지정한 내보내기 폴더가 무시되면 파일이 엉뚱한 디스크로 나간다"
            )
            XCTAssertEqual(
                store.quickExportURL.path,
                "/Volumes/External/negaflow-quick",
                "\(mode)에서 지정한 빠른 내보내기 폴더가 무시되면 파일이 엉뚱한 디스크로 나간다"
            )
        }
    }

    /// 경로를 지정하지 않은 폴더는 예전처럼 루트에서 파생된다.
    func testUnsetFoldersStillDeriveFromTheRoot() {
        let store = makeStore()
        store.locationMode = .custom
        store.rootPath = "/Volumes/External/negaflow"

        XCTAssertEqual(store.exportURL.path, "/Volumes/External/negaflow/Export")
        XCTAssertEqual(store.quickExportURL.path, "/Volumes/External/negaflow/Quick Export")
        XCTAssertEqual(store.thumbnailsURL.path, "/Volumes/External/negaflow/Thumbnails")
    }

    /// 폴더 하나를 고른 것이 라이브러리 루트 전체를 옮기면 안 된다.
    func testChoosingOneFolderDoesNotRelocateTheLibraryRoot() {
        let store = makeStore()
        store.locationMode = .desktop
        let rootBefore = store.rootURL

        store.quickExportPath = "/Volumes/External/negaflow-quick"

        XCTAssertEqual(store.locationMode, .desktop, "폴더 선택이 위치 모드를 바꾸면 안 된다")
        XCTAssertEqual(store.rootURL, rootBefore, "빠른 내보내기 폴더 선택이 루트를 옮기면 안 된다")
        XCTAssertEqual(store.quickExportURL.path, "/Volumes/External/negaflow-quick")
    }

    /// 루트를 직접 지정하는 것은 여전히 사용자 지정 모드를 뜻한다.
    func testChoosingAnExplicitRootStillMeansCustomMode() {
        let store = makeStore()
        store.locationMode = .iCloud

        store.rootPath = "/Volumes/External/negaflow"

        XCTAssertEqual(store.locationMode, .custom)
        XCTAssertEqual(store.rootURL.path, "/Volumes/External/negaflow")
    }

    /// 빈 문자열은 지정하지 않은 것으로 다룬다(루트 파생으로 되돌아간다).
    func testEmptyPathFallsBackToTheRoot() {
        let store = makeStore()
        store.locationMode = .custom
        store.rootPath = "/Volumes/External/negaflow"
        store.quickExportPath = ""

        XCTAssertEqual(store.quickExportURL.path, "/Volumes/External/negaflow/Quick Export")
    }
}
