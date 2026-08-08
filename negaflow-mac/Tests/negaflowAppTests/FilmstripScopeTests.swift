import Chromabase
import Foundation
import XCTest
@testable import negaflowApp

@MainActor
final class FilmstripScopeTests: XCTestCase {
    func testAllScopeKeepsEveryFrame() {
        let frames = [
            makeFrame(folder: "/tmp/roll-a", filmType: .colorNegative),
            makeFrame(folder: "/tmp/roll-b", filmType: .colorPositive),
        ]

        XCTAssertEqual(
            FilmstripScope.all.filtered(frames, reference: frames[0]).map(\.id),
            frames.map(\.id)
        )
    }

    func testMissingReferenceKeepsEveryFrame() {
        let frames = [
            makeFrame(folder: "/tmp/roll-a", filmType: .colorNegative),
            makeFrame(folder: "/tmp/roll-b", filmType: .colorNegative),
        ]

        XCTAssertEqual(
            FilmstripScope.folder.filtered(frames, reference: nil).map(\.id),
            frames.map(\.id)
        )
    }

    func testFolderScopeKeepsOnlyTheActiveFrameFolder() {
        let first = makeFrame(folder: "/tmp/roll-a", filmType: .colorNegative)
        let second = makeFrame(folder: "/tmp/roll-a", filmType: .colorNegative)
        let other = makeFrame(folder: "/tmp/roll-b", filmType: .colorNegative)

        let result = FilmstripScope.folder.filtered([first, second, other], reference: first)

        XCTAssertEqual(result.map(\.id), [first.id, second.id])
    }

    func testProcessScopeKeepsOnlyMatchingDevelopmentProcess() {
        let negative = makeFrame(folder: "/tmp/roll", filmType: .colorNegative)
        let otherNegative = makeFrame(folder: "/tmp/other", filmType: .colorNegative)
        let positive = makeFrame(folder: "/tmp/roll", filmType: .colorPositive)

        let result = FilmstripScope.process.filtered(
            [negative, positive, otherNegative],
            reference: negative
        )

        XCTAssertEqual(result.map(\.id), [negative.id, otherNegative.id])
    }

    func testTargetScopeKeepsOnlyMatchingDevelopTarget() {
        let main = makeFrame(folder: "/tmp/roll", filmType: .colorNegative)
        let alsoMain = makeFrame(folder: "/tmp/roll", filmType: .colorNegative)
        let scanner = makeFrame(folder: "/tmp/roll", filmType: .colorNegative)
        scanner.updateParams { $0.developTarget = .sp3000 }

        let result = FilmstripScope.target.filtered([main, scanner, alsoMain], reference: main)

        XCTAssertEqual(result.map(\.id), [main.id, alsoMain.id])
    }

    private func makeFrame(folder: String, filmType: FilmType) -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent("\(UUID().uuidString).tiff"),
            filmType: filmType
        )
    }
}
