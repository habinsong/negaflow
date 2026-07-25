import Chromabase
import Combine
import XCTest
@testable import negaflowApp

// 관찰 경계 앵커: 고빈도 발행이 AppModel 전역 무효화로 새어나가지 않음을 수치로 고정한다.
// AppModel.objectWillChange 발화 1회 = AppModel 을 관찰하는 모든 뷰(100+ 파일)의 body 재평가.
@MainActor
final class ObservationBoundaryTests: XCTestCase {

    /// 상태 메시지 버스트는 statusCenter 로만 발행되고 AppModel 은 조용해야 한다.
    func testStatusMessageBurstDoesNotInvalidateAppModel() {
        let model = AppModel()
        var appModelEmissions = 0
        var centerEmissions = 0
        let modelSubscription = model.objectWillChange.sink { _ in appModelEmissions += 1 }
        let centerSubscription = model.statusCenter.objectWillChange.sink { _ in
            centerEmissions += 1
        }
        defer {
            modelSubscription.cancel()
            centerSubscription.cancel()
        }

        for index in 0..<100 {
            model.statusMessage = "burst \(index)"
        }

        XCTAssertEqual(centerEmissions, 100, "메시지 갱신은 statusCenter 가 발행해야 한다.")
        XCTAssertEqual(appModelEmissions, 0,
                       "상태 메시지 갱신이 AppModel 전역 무효화로 새면 안 된다.")
        XCTAssertEqual(model.statusMessage, "burst 99", "facade 읽기는 center 값과 일치해야 한다.")
    }

    /// 배치 내보내기 아이템 틱(프레임당 2회)은 진행 뷰만 갱신해야 한다.
    /// AppModel 은 isRunning 전이(시작/종료)에만 반응한다 — canExportSelection 갱신용.
    func testExportBatchItemTicksDoNotInvalidateAppModel() {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-observation-anchor.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let options = ExportOptions(
            jpegQuality: 0.8,
            tiffCompression: .lzw,
            tiffBitDepth: .eight,
            metadataPolicy: .copyrightOnly,
            outputSharpening: 0.45,
            outputSharpeningMedium: .glossyPaper
        )
        let plans = (0..<50).map { index in
            ExportBatchPlan(
                frame: frame,
                outputURL: URL(fileURLWithPath: "/tmp/negaflow-anchor-out-\(index).jpg"),
                format: .jpeg,
                writeSidecar: false,
                writeMainFlatMaster: false,
                writeOriginalRaw: false,
                options: options
            )
        }
        var appModelEmissions = 0
        let subscription = model.objectWillChange.sink { _ in appModelEmissions += 1 }
        defer { subscription.cancel() }

        model.exportBatchStore.begin(plans)   // isRunning false→true: 1회
        for plan in plans {
            model.exportBatchStore.markRunning(plan.id)
            model.exportBatchStore.markFinished(
                plan.id,
                result: .completed(outputURL: plan.outputURL, pairedURLs: [])
            )
        }
        model.exportBatchStore.finish()       // isRunning true→false: 1회

        XCTAssertEqual(model.exportBatchStore.completedCount, 50)
        XCTAssertEqual(appModelEmissions, 2,
                       "아이템 틱 100회가 AppModel 전역 무효화로 새면 안 된다(시작/종료 2회만 허용).")
    }

    /// 저장 세대 카운터 bump(현상 슬라이더 틱마다 발생)는 모델 내부 상태라
    /// AppModel 전역 무효화를 일으키면 안 된다.
    func testDirtyGenerationBumpsDoNotInvalidateAppModel() {
        let model = AppModel()
        var appModelEmissions = 0
        let subscription = model.objectWillChange.sink { _ in appModelEmissions += 1 }
        defer { subscription.cancel() }

        for _ in 0..<100 {
            model.markLibraryCatalogDirty()
        }

        XCTAssertEqual(model.libraryCatalogDirtyGeneration, 100)
        XCTAssertEqual(appModelEmissions, 0,
                       "세대 카운터는 반응형 소비자가 없다 — 발행하면 순수 낭비다.")
    }
}
