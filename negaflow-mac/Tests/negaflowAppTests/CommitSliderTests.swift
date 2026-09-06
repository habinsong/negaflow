import XCTest
import AppKit
@testable import negaflowApp

@MainActor
final class CommitSliderTests: XCTestCase {
    func testDisabledGestureCannotCommitAfterReenabled() {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.synchronize(1.8, ownerID: UUID())
        var commits: [Double] = []
        control.onCommit = { commits.append($0) }
        control.beginEditing()
        control.doubleValue = 2.4
        control.isEnabled = false
        control.isEnabled = true
        control.valueChanged()
        control.finishEditing()
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(control.doubleValue, 1.8)
    }

    func testDisabledAccessibilityActionCannotCommit() {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.synchronize(1.8, ownerID: UUID())
        var commits = 0
        control.onCommit = { _ in commits += 1 }
        control.isEnabled = false
        control.doubleValue = 2.4
        control.valueChanged()
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(control.doubleValue, 1.8)
    }

    func testGammaTrackingUsesTenthsWithoutAcceptingStaleModelValues() {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.step = 0.1; control.snapsToStep = true
        let owner = UUID()
        control.synchronize(2.19921875, ownerID: owner)
        XCTAssertEqual(control.doubleValue, 2.2)
        var commits: [Double] = []
        var drafts: [Double] = []
        control.onCommit = { commits.append($0) }
        control.onDraft = { if let value = $0 { drafts.append(value) } }
        control.beginEditing()
        for (input, expected) in [(2.22, 2.2), (2.25, 2.3), (2.349, 2.3), (2.35, 2.4), (4.0, 4.0)] {
            control.doubleValue = input
            control.valueChanged()
            control.synchronize(2.19921875, ownerID: owner)
            XCTAssertEqual(control.doubleValue, expected)
        }
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(drafts, [2.2, 2.3, 2.3, 2.4, 4])
        control.finishEditing()
        XCTAssertEqual(commits, [4])
    }

    func testGammaArrowStartsFromRoundedStoredValueAndUsesOneTenth() throws {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.step = 0.1; control.snapsToStep = true
        control.synchronize(2.19921875, ownerID: UUID())
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        control.keyDown(with: event)
        XCTAssertEqual(control.doubleValue, 2.3)
        control.finishEditing()
    }

    func testEscapeAfterOwnerChangeKeepsNewOwnersValue() {
        let control = CommitSliderControl()
        control.minValue = 0.5; control.maxValue = 1.5
        control.synchronize(1, ownerID: UUID())
        var commits = 0
        control.onCommit = { _ in commits += 1 }
        control.beginEditing()
        control.doubleValue = 1.4
        control.synchronize(0.75, ownerID: UUID())
        control.cancelOperation(nil)
        control.finishEditing()
        XCTAssertEqual(control.doubleValue, 0.75)
        XCTAssertEqual(commits, 0)
    }

    func testArrowKeyRepeatCommitsOnceOnRelease() throws {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.synchronize(1.8, ownerID: UUID())
        var commits: [Double] = []
        control.onCommit = { commits.append($0) }
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        let up = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        control.keyDown(with: down)
        control.keyDown(with: down)
        XCTAssertTrue(commits.isEmpty)
        control.keyUp(with: up)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0], 1.82, accuracy: 1e-12)
    }
    func testTrackingIgnoresStaleRefreshAndCommitsOnce() {
        let control = CommitSliderControl()
        XCTAssertTrue(control.acceptsFirstResponder)
        control.minValue = 0.1; control.maxValue = 4
        let owner = UUID()
        var commits: [Double] = []
        var drafts: [Double] = []
        control.onCommit = { commits.append($0) }
        control.onDraft = { if let value = $0 { drafts.append(value) } }
        control.synchronize(1.8, ownerID: owner)
        control.beginEditing()
        for index in 0...200 {
            let value = 1.8 + Double(index) / 100
            control.doubleValue = value
            control.valueChanged()
            control.synchronize(1.8, ownerID: owner)
            XCTAssertEqual(control.doubleValue, value, accuracy: 1e-12)
        }
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(drafts.count, 201)
        control.finishEditing()
        control.finishEditing()
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0], 3.8, accuracy: 1e-12)
    }

    func testFrameChangeAndEscapeNeverCommitOldGesture() {
        for changeOwner in [true, false] {
            let control = CommitSliderControl()
            control.minValue = 0.5; control.maxValue = 1.5
            control.synchronize(1, ownerID: UUID())
            var commits = 0
            control.onCommit = { _ in commits += 1 }
            control.beginEditing()
            control.doubleValue = 1.4
            if changeOwner {
                control.synchronize(0.8, ownerID: UUID())
                // 이전 mouse tracking loop에서 늦게 도착한 값입니다.
                control.doubleValue = 1.49
            }
            else { control.cancelOperation(nil) }
            control.valueChanged()
            control.finishEditing()
            XCTAssertEqual(commits, 0)
            XCTAssertEqual(control.doubleValue, changeOwner ? 0.8 : 1)
        }
    }

    func testAccessibilityChangeCommitsWithoutPointerSession() {
        let control = CommitSliderControl()
        control.minValue = 0.1; control.maxValue = 4
        control.synchronize(2.2, ownerID: UUID())
        var committed = 0.0
        control.onCommit = { committed = $0 }
        control.doubleValue = 2.21
        control.valueChanged()
        XCTAssertEqual(committed, 2.21)
    }
}
