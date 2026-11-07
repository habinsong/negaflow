import AppKit
import XCTest
@testable import negaflowApp

/// 크롭 중 조합키 + 드래그로 그린 기준선을 수평·수직으로 맞추는 계산과, 그 조합키 설정.
@MainActor
final class StraightenLineToolTests: XCTestCase {
    func testLineIsLeveledWhicheverWayItWasDrawn() throws {
        // 오른쪽으로 갈수록 3° 내려가는 선(화면 y 아래)은 반시계 3° 로 편다.
        let drop = tan(3 * Double.pi / 180) * 400
        let right = try XCTUnwrap(CropOverlayGeometry.straightenCorrection(
            from: CGPoint(x: 100, y: 200), to: CGPoint(x: 500, y: 200 + drop)))
        XCTAssertEqual(right, -3, accuracy: 1e-9)
        // 같은 선을 반대 방향으로 그려도 같다.
        let left = try XCTUnwrap(CropOverlayGeometry.straightenCorrection(
            from: CGPoint(x: 500, y: 200 + drop), to: CGPoint(x: 100, y: 200)))
        XCTAssertEqual(left, -3, accuracy: 1e-9)
    }

    func testSteepLineIsTreatedAsAVertical() throws {
        // 아래로 그린 거의 수직인 선이 오른쪽으로 2° 기울면(화면 각 88°) 시계 2° 로 세운다.
        let lean = tan(2 * Double.pi / 180) * 300
        let down = try XCTUnwrap(CropOverlayGeometry.straightenCorrection(
            from: CGPoint(x: 200, y: 100), to: CGPoint(x: 200 + lean, y: 400)))
        XCTAssertEqual(down, 2, accuracy: 1e-9)
        let up = try XCTUnwrap(CropOverlayGeometry.straightenCorrection(
            from: CGPoint(x: 200 + lean, y: 400), to: CGPoint(x: 200, y: 100)))
        XCTAssertEqual(up, 2, accuracy: 1e-9)
    }

    func testShortTwitchDoesNothing() {
        XCTAssertNil(CropOverlayGeometry.straightenCorrection(
            from: CGPoint(x: 10, y: 10), to: CGPoint(x: 14, y: 13)))
    }

    func testGestureModifiersDefaultToCommandAndOptionAndRejectSharedKeys() throws {
        let suite = "negaflow.gesture-modifiers.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkflowShortcutStore(defaults: defaults)

        XCTAssertEqual(store.gestureModifier(for: .straightenWithLine), .command)
        XCTAssertEqual(store.gestureModifier(for: .straightenGrid), .option)
        // 두 동작이 같은 키를 가질 수 없다.
        XCTAssertFalse(store.setGestureModifier(.option, for: .straightenWithLine))
        // ⌃ 클릭은 오른쪽 클릭이라 드래그에 쓰지 않는다.
        XCTAssertFalse(store.setGestureModifier(.control, for: .straightenWithLine))
        // 조합키는 하나만.
        XCTAssertFalse(store.setGestureModifier([.command, .shift], for: .straightenWithLine))

        XCTAssertTrue(store.setGestureModifier(.shift, for: .straightenWithLine))
        XCTAssertTrue(store.setGestureModifier(.command, for: .straightenGrid))
        let reloaded = WorkflowShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.gestureModifier(for: .straightenWithLine), .shift)
        XCTAssertEqual(reloaded.gestureModifier(for: .straightenGrid), .command)

        // 기준선을 기본(⌘)으로 되돌리면 ⌘ 를 쓰던 격자도 기본으로 돌아가 겹치지 않는다.
        reloaded.resetGestureModifier(for: .straightenWithLine)
        XCTAssertEqual(reloaded.gestureModifier(for: .straightenWithLine), .command)
        XCTAssertEqual(reloaded.gestureModifier(for: .straightenGrid), .option)
    }

    func testHandEditedSettingsThatShareAKeyFallBackToDefaults() throws {
        let suite = "negaflow.gesture-modifiers.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([
                "straightenWithLine": WorkflowShortcutModifiers.option.rawValue,
                "straightenGrid": WorkflowShortcutModifiers.option.rawValue,
            ]),
            forKey: "workflow.gestureModifiers.overrides"
        )
        let store = WorkflowShortcutStore(defaults: defaults)
        XCTAssertEqual(store.gestureModifier(for: .straightenWithLine), .command)
        XCTAssertEqual(store.gestureModifier(for: .straightenGrid), .option)
    }

    func testHeldModifierAllowsOtherKeysToBeHeldToo() {
        XCTAssertTrue(WorkflowShortcutModifiers.command.isHeld(in: [.command, .option]))
        XCTAssertFalse(WorkflowShortcutModifiers.command.isHeld(in: [.option]))
        XCTAssertFalse(WorkflowShortcutModifiers([]).isHeld(in: [.command]))
    }
}
