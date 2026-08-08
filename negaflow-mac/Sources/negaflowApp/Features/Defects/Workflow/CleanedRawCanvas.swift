import CoreGraphics
import Foundation

/// cleaned raw 증분 합성 캔버스.
///
/// 기존 빌드는 편집 1회마다 "베이스 + 패치 체인"을 CIContext 로 풀프레임 RGBA16 flatten(수백 MB
/// 렌더 + GPU 리드백)했다 — 편집 비용이 결함 크기가 아니라 이미지 면적에 비례하던 주범. 여기서는
/// 풀해상도 픽셀을 CGBitmapContext 에 유지하고, 편집은 패치 rect 만 CPU 블릿한 뒤
/// `makeImage()`(CoW 스냅샷)를 커밋 픽셀로 쓴다. 스냅샷은 페이지 copy-on-write 라 다음 편집이
/// 실제로 그린 패치 페이지만 물리 복사된다 — N번째 제거가 결함 크기 비례 비용이 된다.
///
/// 좌표: DefectPatch.rect 는 CIImage(y-up) — CGContext 기본 좌표(y-up, 원점 좌하단)와 같아
/// 그대로 draw 한다. CGImage.cropping(to:) 만 top-left(y-down) 이므로 복원 블릿에서 뒤집는다.
///
/// 동시성: 빌드 태스크는 한 번에 하나만 유효하지만 취소된 이전 태스크가 늦게 도착할 수 있어
/// 모든 픽셀 변형+스냅샷을 한 락 구간에서 원자적으로 수행한다. 내용 추적은 CGImage 정체성
/// (스냅샷/베이스 객체)으로 한다 — CGImage 는 불변이라 정체성 일치 = 픽셀 일치다.
/// 정체성 비교는 반드시 강한 참조 + `===` 로 한다: 참조 없이 주소(ObjectIdentifier)만 저장하면
/// 해제된 이미지의 주소를 새 이미지가 재사용할 때 잘못된 fast path 로 stale 픽셀을 돌려줄 수
/// 있다. 스냅샷은 캔버스와 CoW 페이지를 공유하므로 보유 비용은 이후 그린 패치 페이지뿐이다.
final class CleanedRawCanvas: @unchecked Sendable {
    let width: Int
    let height: Int
    private let context: CGContext
    private let lock = NSLock()
    /// 캔버스 픽셀과 동일한 이미지(직전 composite 반환 스냅샷 또는 방금 블릿한 base).
    /// nil = 내용 불명.
    private var contentImage: CGImage?
    /// 직전 composite 의 base 와 그 위에 그린 rect 들 — 같은 base 로 다시 합성(라이브
    /// 강도 드래그)할 때 rect 만 base 로 되돌리고 다시 그린다(풀 블릿 없음).
    private var lastBase: CGImage?
    private var lastAppliedRects: [CGRect] = []

    init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 16, bytesPerRow: 0,
            space: linearColorSpace, bitmapInfo: bitmapInfo
        ) ?? CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 16, bytesPerRow: 0,
            space: linearColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        self.context = context
        self.width = width
        self.height = height
    }

    /// base 위에 patches 를 순서대로(강도 블렌드 포함) 그려 스냅샷을 돌려준다.
    ///  • 캔버스 내용 == base(직전 스냅샷을 그대로 base 로 준 증분 append) → 패치만 그린다.
    ///  • 직전 composite 와 같은 base(라이브 드래그 재합성) → 이전 rect 만 base 로 복원 후 그린다.
    ///  • 그 외 → base 풀 블릿 1회 후 그린다(CPU memcpy — GPU 풀 flatten 보다 싸다).
    /// 강도 s 블렌드는 setAlpha(s) + .normal(불투명 소스라 s·patch + (1−s)·dst) — CIMix 와 동일한
    /// 선형 블렌드다(16bit 반올림 1스텝 이내).
    func composite(base: CGImage,
                   patches: [(patch: DefectPatch, strength: Double)]) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard base.width == width, base.height == height else { return nil }
        if contentImage !== base {
            if lastBase === base, contentImage != nil, !lastAppliedRects.isEmpty {
                for rect in lastAppliedRects {
                    guard restoreRegion(from: base, rect: rect) else { return nil }
                }
            } else {
                context.setAlpha(1)
                context.setBlendMode(.copy)
                context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            contentImage = base
        }
        var rects: [CGRect] = []
        rects.reserveCapacity(patches.count)
        for (patch, strength) in patches {
            let s = min(1.0, max(0.0, strength))
            guard s > 1e-3 else { continue }
            context.setBlendMode(.normal)
            context.setAlpha(CGFloat(s))
            context.draw(patch.image, in: patch.rect)
            rects.append(patch.rect)
        }
        context.setAlpha(1)
        lastBase = base
        lastAppliedRects = rects
        guard let snapshot = context.makeImage() else {
            contentImage = nil
            return nil
        }
        contentImage = snapshot
        return snapshot
    }

    /// base 의 rect(y-up) 영역을 캔버스 같은 자리에 복사해 되돌린다.
    private func restoreRegion(from base: CGImage, rect: CGRect) -> Bool {
        let integral = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard integral.width >= 1, integral.height >= 1 else { return true }
        // CGImage.cropping 좌표는 top-left(y-down).
        let cropRect = CGRect(x: integral.minX,
                              y: CGFloat(height) - integral.maxY,
                              width: integral.width, height: integral.height)
        guard let piece = base.cropping(to: cropRect) else { return false }
        context.setAlpha(1)
        context.setBlendMode(.copy)
        context.draw(piece, in: integral)
        return true
    }
}
