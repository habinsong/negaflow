import XCTest
@testable import negaflowApp

// MARK: - 가져온 사진의 출처 폴더명
//
// 내보내기 위치는 `<루트>/<날짜>/<출처 폴더>` 다. 예전에는 개별 파일 가져오기를 전부 `default` 로
// 묶어서, 같은 폴더의 사진이라도 파일로 먼저 가져온 것만 `default/` 로 빠지고 나중에 폴더째
// 가져온 나머지는 폴더명으로 갈라졌다(실기: negaflow_test 15장 중 한 장만 default/ 로 저장됨).
// 출처는 가져온 방식이 아니라 원본이 있던 자리로 정한다.
final class ImportStorageGroupTests: XCTestCase {
    func testImportGroupNameUsesTheParentFolderOfTheSource() {
        let url = URL(fileURLWithPath: "/Users/someone/Pictures/negaflow_test/frame_4.tiff")
        XCTAssertEqual(FrameStorageNaming.importGroupName(forSourceURL: url), "negaflow_test")
    }

    func testFilesFromTheSameFolderShareOneGroupRegardlessOfHowTheyWereImported() {
        let folder = URL(fileURLWithPath: "/Users/someone/Downloads/roll-07", isDirectory: true)
        let single = folder.appendingPathComponent("frame_4.tiff")
        let batch = folder.appendingPathComponent("frame_5.tiff")

        XCTAssertEqual(
            FrameStorageNaming.importGroupName(forSourceURL: single),
            FrameStorageNaming.importGroupName(forSourceURL: batch),
            "한 폴더의 사진은 가져온 방식과 무관하게 같은 출처 폴더로 모여야 한다."
        )
    }

    func testGroupNameFallsBackToDefaultWhenThereIsNoParentFolderName() {
        XCTAssertEqual(
            FrameStorageNaming.importGroupName(forSourceURL: URL(fileURLWithPath: "/frame.tiff")),
            FrameStorageNaming.defaultImportGroup
        )
    }

    func testResolvedGroupNameKeepsAnExplicitGroup() {
        let url = URL(fileURLWithPath: "/Users/someone/Downloads/roll-07/frame_4.tiff")
        XCTAssertEqual(
            FrameStorageNaming.resolvedGroupName(storedGroup: "HP5PLUS", sourceURL: url),
            "HP5PLUS",
            "스캔처럼 출처가 정해진 프레임은 그 이름을 그대로 쓴다."
        )
    }

    func testResolvedGroupNameHealsLegacyDefaultEntries() {
        let url = URL(fileURLWithPath: "/Users/someone/Downloads/negaflow_test/frame_4.tiff")
        // 카탈로그에 이미 default 로 저장된 예전 프레임 — 카탈로그를 고쳐 쓰지 않고도
        // 같은 폴더의 나머지 사진과 한곳으로 모여야 한다.
        XCTAssertEqual(
            FrameStorageNaming.resolvedGroupName(
                storedGroup: FrameStorageNaming.defaultImportGroup,
                sourceURL: url
            ),
            "negaflow_test"
        )
        XCTAssertEqual(
            FrameStorageNaming.resolvedGroupName(storedGroup: nil, sourceURL: url),
            "negaflow_test"
        )
    }

    func testResolvedGroupNameSanitizesPathSeparators() {
        let url = URL(fileURLWithPath: "/Users/someone/Downloads/roll/frame.tiff")
        XCTAssertEqual(
            FrameStorageNaming.resolvedGroupName(storedGroup: "a/b:c", sourceURL: url),
            "abc",
            "폴더명에 쓸 수 없는 문자는 저장 전에 걸러진다."
        )
    }
}
