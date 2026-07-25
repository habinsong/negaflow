import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - ThumbnailDiskCache
//
// 필름스트립/라이브러리 썸네일의 디스크 백킹(썸네일 프리뷰 캐시 격). 메모리 FIFO 는
// 그대로 두고, 정착 시점(가져오기 직후 원본 프리뷰 · 현상 정착 패스)마다 JPEG 로 덮어쓴다.
// 프레임별로 마지막 요청만 남기는 코얼레싱 + 단일 유틸리티 큐라서 연속 현상 중에도 인코딩이
// 중복되지 않고 메인 스레드 IO 가 없다. 캐시이므로 전부 지워도 원본에서 재생성된다.
final class ThumbnailDiskCache: @unchecked Sendable {
    private static let queueLabel = "negaflow.thumbnail-disk-cache"
    private let queue = DispatchQueue(label: ThumbnailDiskCache.queueLabel, qos: .utility)
    private let lock = NSLock()
    private var versions: [UUID: UInt64] = [:]
    private var clearGeneration: UInt64 = 0

    /// 썸네일을 디스크에 저장한다(같은 프레임의 진행 중 요청은 최신 것으로 대체).
    func store(_ image: CGImage, for frameID: UUID, at url: URL) {
        locked {
            let version = (versions[frameID] ?? 0) &+ 1
            versions[frameID] = version
            let generation = clearGeneration
            queue.async { [weak self] in
                guard let self else { return }
                let isLatest = self.locked {
                    self.clearGeneration == generation && self.versions[frameID] == version
                }
                guard isLatest else { return }
                Self.write(image, to: url)
            }
        }
    }

    /// 해당 프레임에 먼저 예약된 저장 블록을 무효화한다.
    private func invalidatePendingStore(for frameID: UUID) {
        versions[frameID] = (versions[frameID] ?? 0) &+ 1
    }

    /// 디스크 썸네일 로드. 압축 데이터를 lazy 디코드하는 NSImage 로 돌려준다(대량 로드에 안전).
    nonisolated static func load(at url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    nonisolated static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 같은 프레임의 대기 중 쓰기를 취소한 뒤 직렬 IO 큐에서 파일을 제거한다.
    /// 이미 실행 중인 인코딩이 있더라도 제거 작업이 그 뒤에 실행되므로 파일이 되살아나지 않는다.
    func remove(for frameID: UUID, at url: URL) {
        locked {
            invalidatePendingStore(for: frameID)
            queue.async {
                Self.remove(at: url)
            }
        }
    }

    /// 대기 중인 모든 쓰기를 취소한 뒤 캐시 루트를 제거한다. 이 호출 뒤에 들어온 저장 요청은
    /// 제거 작업 다음에 실행되므로 새 썸네일만 다시 생성된다.
    func clear(at url: URL) async {
        await withCheckedContinuation { continuation in
            locked {
                clearGeneration &+= 1
                versions.removeAll()
                queue.async {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume()
                }
            }
        }
    }

    /// 테스트와 종료 동기화를 위해 현재 큐에 예약된 IO가 끝날 때까지 기다린다.
    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume()
            }
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private nonisolated static func write(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        try? (data as Data).write(to: url, options: .atomic)
    }
}
