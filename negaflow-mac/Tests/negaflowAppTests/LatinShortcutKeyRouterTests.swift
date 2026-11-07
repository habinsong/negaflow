import AppKit
import XCTest
@testable import negaflowApp

/// 한글 입력 상태에서 단일 키 단축키(크롭 R 등)를 라틴 글자로 다시 찾는 규칙.
final class LatinShortcutKeyRouterTests: XCTestCase {
    func testOnlyNonLatinCharactersWithoutCommandModifiersAreRemapped() {
        XCTAssertTrue(LatinShortcutKeyRouter.needsLatinFallback(characters: "ㄱ", modifiers: []))
        XCTAssertTrue(LatinShortcutKeyRouter.needsLatinFallback(characters: "ㅂ", modifiers: [.shift]))
        // 라틴 글자는 AppKit 이 이미 맞춘다.
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: "r", modifiers: []))
        // ⌘·⌃·⌥ 조합은 건드리지 않는다.
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: "ㄱ", modifiers: [.command]))
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: "ㄱ", modifiers: [.control]))
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: "ㄱ", modifiers: [.option]))
        // 화살표·기능 키는 그대로 둔다.
        let upArrow = String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: upArrow, modifiers: []))
        XCTAssertFalse(LatinShortcutKeyRouter.needsLatinFallback(characters: nil, modifiers: []))
    }

    /// 키 자리 15(ANSI R)는 ASCII 자판에서 r, ⇧ 와 함께면 R 이다.
    func testKeyPositionTranslatesThroughTheASCIICapableLayout() throws {
        let plain = try XCTUnwrap(LatinShortcutKeyRouter.latinCharacters(keyCode: 15, shift: false))
        XCTAssertEqual(plain.lowercased(), "r")
        let shifted = try XCTUnwrap(LatinShortcutKeyRouter.latinCharacters(keyCode: 15, shift: true))
        XCTAssertEqual(shifted, shifted.uppercased())
    }
}
