import XCTest
@testable import negaflowApp

/// 사용자 프리셋 이름 규칙입니다. 프리셋은 나중에 목록에서 골라 쓰는 것이라 이름이 곧 정체이며,
/// 같은 이름이 둘이면 어느 것을 고르고 지우는지 알 수 없습니다.
final class DevelopUserPresetNamingTests: XCTestCase {
    private func auto(_ index: Int) -> String { "프리셋 \(index)" }

    func testEmptyNameTakesTheFirstFreeNumber() {
        XCTAssertEqual(
            DevelopUserPresetNaming.resolve(requested: "", existing: [], autoName: auto),
            "프리셋 1"
        )
        XCTAssertEqual(
            DevelopUserPresetNaming.resolve(requested: "   ", existing: ["프리셋 1"], autoName: auto),
            "프리셋 2"
        )
        // 개수+1 이 아니라 비어 있는 첫 번호입니다. 가운데를 지운 목록에서 갈립니다.
        XCTAssertEqual(
            DevelopUserPresetNaming.resolve(
                requested: "",
                existing: ["프리셋 1", "프리셋 3"],
                autoName: auto
            ),
            "프리셋 2"
        )
    }

    func testTypedNameIsKeptAndTrimmed() {
        XCTAssertEqual(
            DevelopUserPresetNaming.resolve(requested: "Portra", existing: [], autoName: auto),
            "Portra"
        )
        XCTAssertEqual(
            DevelopUserPresetNaming.resolve(requested: "  Portra  ", existing: [], autoName: auto),
            "Portra"
        )
    }

    func testDuplicateNameIsRejected() {
        XCTAssertNil(
            DevelopUserPresetNaming.resolve(requested: "Portra", existing: ["Portra"], autoName: auto)
        )
        XCTAssertNil(
            DevelopUserPresetNaming.resolve(
                requested: "  Portra ",
                existing: ["Portra"],
                autoName: auto
            )
        )
        // 목록에서 사람이 읽고 고르는 이름이라 대소문자만 다른 것도 같은 이름으로 봅니다.
        XCTAssertNil(
            DevelopUserPresetNaming.resolve(requested: "portra", existing: ["Portra"], autoName: auto)
        )
        // 자동 이름과 같은 이름을 손으로 적은 경우도 겹칩니다.
        XCTAssertNil(
            DevelopUserPresetNaming.resolve(
                requested: "프리셋 1",
                existing: ["프리셋 1"],
                autoName: auto
            )
        )
    }
}
