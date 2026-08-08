import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LocalAdjustmentWorkflowTests: XCTestCase {
    func testCanvasMaskFactoryCreatesEverySupportedMask() throws {
        let points = [
            LocalDodgeBurnPoint(x: 0.2, y: 0.2),
            LocalDodgeBurnPoint(x: 0.7, y: 0.3),
            LocalDodgeBurnPoint(x: 0.5, y: 0.8),
        ]
        for kind in LocalDodgeBurnMask.Kind.allCases {
            let mask = try XCTUnwrap(LocalAdjustmentMaskFactory.make(
                kind: kind,
                points: points,
                thickness: 0.08,
                feather: 0.4
            ))
            XCTAssertEqual(mask.kind, kind)
        }
        XCTAssertNil(LocalAdjustmentMaskFactory.make(
            kind: .polygon,
            points: Array(points.prefix(2)),
            thickness: 0.08,
            feather: 0.4
        ))
    }

    func testRadialMaskRadiusUsesTheShortPixelDimension() throws {
        let mask = try XCTUnwrap(LocalAdjustmentMaskFactory.make(
            kind: .radial,
            points: [
                LocalDodgeBurnPoint(x: 0.5, y: 0.5),
                LocalDodgeBurnPoint(x: 0.75, y: 0.5),
            ],
            thickness: 0.08,
            feather: 0.4,
            imageSize: CGSize(width: 200, height: 100)
        ))

        XCTAssertEqual(mask.radius, 0.5, accuracy: 1e-9)
    }

    func testCreateEditVisibilityCopyPasteAndUndoRedo() throws {
        let model = AppModel()
        let frame = makeFrame(index: 1)
        model.frames = [frame]
        let undoManager = UndoManager()
        model.catalogUndoManager = undoManager
        let session = LocalAdjustmentSession()
        session.amount = 0.62
        let mask = try XCTUnwrap(LocalAdjustmentMaskFactory.make(
            kind: .radial,
            points: [
                LocalDodgeBurnPoint(x: 0.5, y: 0.5),
                LocalDodgeBurnPoint(x: 0.75, y: 0.5),
            ],
            thickness: session.brushThickness,
            feather: session.feather
        ))
        let adjustment = session.makeAdjustment(mask: mask)

        model.addLocalAdjustment(adjustment, to: frame)
        XCTAssertEqual(frame.params.localDodgeBurn, [adjustment])
        undoManager.undo()
        XCTAssertTrue(frame.params.localDodgeBurn.isEmpty)
        undoManager.redo()
        XCTAssertEqual(frame.params.localDodgeBurn, [adjustment])

        model.updateLocalAdjustment(id: adjustment.id, on: frame) {
            $0.amount = 0.8
            $0.isEnabled = false
        }
        XCTAssertEqual(frame.params.localDodgeBurn[0].amount, 0.8, accuracy: 1e-9)
        XCTAssertFalse(frame.params.localDodgeBurn[0].isEnabled)
        undoManager.undo()
        XCTAssertEqual(frame.params.localDodgeBurn, [adjustment])

        session.copy(adjustment)
        let pasted = try XCTUnwrap(session.pastedAdjustment())
        XCTAssertNotEqual(pasted.id, adjustment.id)
        XCTAssertEqual(pasted.mask, adjustment.mask)
        model.addLocalAdjustment(pasted, to: frame)
        XCTAssertEqual(frame.params.localDodgeBurn.count, 2)
    }

    func testDevelopSettingsCopyPasteIncludesLocalAdjustments() {
        let model = AppModel()
        let source = makeFrame(index: 1)
        let destination = makeFrame(index: 2)
        source.updateParams {
            $0.localDodgeBurn = [LocalDodgeBurnAdjustment(
                mode: .burn,
                amount: 0.45,
                mask: .linear(
                    start: LocalDodgeBurnPoint(x: 0.1, y: 0.2),
                    end: LocalDodgeBurnPoint(x: 0.8, y: 0.7),
                    feather: 0.6
                )
            )]
        }
        model.frames = [source, destination]

        model.copyDevelopSettings(from: source)
        model.pasteDevelopSettings(to: destination)

        XCTAssertEqual(destination.params.localDodgeBurn, source.params.localDodgeBurn)
    }

    private func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("local-adjustment-\(UUID().uuidString).tif"),
            filmType: .colorPositive
        )
    }
}
