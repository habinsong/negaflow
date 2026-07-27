import AppKit
import XCTest
@testable import negaflowApp

// 캐시에서 축출된 프레임을 다시 열었을 때 재현상이 걸리는지 검증.
//
// 실제 버그(2026-07-27): 첫 썸네일 시드 태스크 참조가 완료 뒤에도 남아 있었고,
// selectedFrameNeedsDevelopment 가 그 참조를 "시드 진행 중"으로 읽었다. 그래서 한 번이라도 시드된
// 프레임은 FIFO 축출로 developedImage 가 사라져도 영영 재현상되지 않고 썸네일(저해상도)에
// 머물렀다. 슬라이더를 움직이면 requestDevelop 이 직접 걸려 복구되고, 앱을 다시 켜면 참조가
// 사라져 정상으로 보이던 것이 이 때문이다.
@MainActor
final class EvictedFrameRedevelopTests: XCTestCase {
    // setUp/tearDown 은 nonisolated 라 MainActor 격리된 가변 상태를 만질 수 없다.
    // 경로만 담은 불변 let 을 두고 폴더째 지운다.
    private let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("negaflow-evict-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    /// 소스가 온라인이어야 실제 현상 판정 경로를 탄다 — 파일이 없으면 오프라인 분기로 빠진다.
    private func makeFrame(withImage: Bool = false) -> ScanFrame {
        let url = sandbox.appendingPathComponent("\(UUID().uuidString).png")
        if withImage, let data = Self.onePixelPNG() {
            try? data.write(to: url)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        }
        return ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative)
    }

    /// 시드가 실제로 디코드할 수 있는 최소 이미지.
    private static func onePixelPNG() -> Data? {
        let size = NSSize(width: 2, height: 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.gray.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: 축출된 프레임은 다시 현상해야 한다

    func testEvictedFrameNeedsDevelopmentAgain() {
        let model = AppModel()
        let frame = makeFrame()
        model.frames = [frame]
        frame.hasDevelopedOnce = true
        frame.developedIsSettled = true

        // 축출 = 풀해상도 버퍼만 내려놓는다.
        model.evictDevelopBuffers(frame)

        XCTAssertNil(frame.developedImage)
        XCTAssertTrue(model.selectedFrameNeedsDevelopment(frame),
                      "축출로 현상 결과가 사라졌으면 다시 현상해야 한다")
    }

    // MARK: 완료된 시드가 재현상을 막지 않는다

    func testCompletedThumbnailSeedDoesNotBlockRedevelopment() async throws {
        let model = AppModel()
        let frame = makeFrame(withImage: true)
        model.frames = [frame]

        // 실제 시드 경로를 태운다.
        model.seedInitialThumbnail(for: frame, from: frame.rawScanURL)
        let seed = try XCTUnwrap(frame.initialThumbnailSeedTask)
        await seed.value

        XCTAssertNil(frame.initialThumbnailSeedTask,
                     "끝난 시드가 '진행 중'으로 남으면 축출된 프레임이 영영 재현상되지 않는다")
        XCTAssertTrue(model.selectedFrameNeedsDevelopment(frame),
                      "시드가 끝났으면 현상 결과가 없는 프레임은 현상 대상이다")
    }

    // MARK: 진행 중인 시드는 여전히 현상을 미룬다

    func testRunningThumbnailSeedStillDefersDevelopment() async {
        let model = AppModel()
        let frame = makeFrame()
        model.frames = [frame]

        let started = expectation(description: "seed started")
        frame.initialThumbnailSeedGeneration += 1
        frame.initialThumbnailSeedTask = Task<Void, Never> {
            started.fulfill()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertFalse(model.selectedFrameNeedsDevelopment(frame),
                       "시드가 도는 동안에는 현상을 미뤄 중복 시작을 막는다")
        frame.initialThumbnailSeedTask?.cancel()
    }

    // MARK: 새 시드가 옛 태스크 참조에 지워지지 않는다(레이스 가드)

    func testStaleSeedDoesNotClearNewerTaskReference() async {
        let frame = makeFrame()

        frame.initialThumbnailSeedGeneration += 1
        let staleGeneration = frame.initialThumbnailSeedGeneration
        let stale = Task<Void, Never> { [weak frame] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let frame, frame.initialThumbnailSeedGeneration == staleGeneration {
                frame.initialThumbnailSeedTask = nil
            }
        }

        // 옛 태스크가 끝나기 전에 새 시드를 설치한다.
        frame.initialThumbnailSeedGeneration += 1
        let fresh = Task<Void, Never> { try? await Task.sleep(nanoseconds: 200_000_000) }
        frame.initialThumbnailSeedTask = fresh

        await stale.value
        XCTAssertNotNil(frame.initialThumbnailSeedTask,
                        "끝난 옛 시드가 새로 설치된 참조를 지우면 안 된다")
        fresh.cancel()
    }
}
