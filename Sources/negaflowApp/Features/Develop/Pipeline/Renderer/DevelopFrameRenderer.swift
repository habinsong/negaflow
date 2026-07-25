import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

enum DevelopFrameRenderer {

    // 풀해상도 프리뷰 프록시 상한(정착 패스). 익스포트는 별도 풀해상도 경로라 영향받지 않는다.
    static let fullMaxDimension: CGFloat = 3600
    // 인터랙티브 프록시 폴백(캔버스 표시 크기를 아직 모를 때). 평소엔 표시 크기 기반 적응형.
    static let interactiveMaxDimension: CGFloat = 1600
    static let fastPreviewMaxDimension: CGFloat = 720
    // 적응형 인터랙티브 프록시 하한/양자화 스텝. 표시 크기보다 작게 렌더하면 업스케일로
    // 흐려졌다가 정착 때 선명해지는 "해상도 펌핑"이 보이므로, 표시 픽셀 이상으로 올림한다.
    static let interactiveMinDimension: CGFloat = 1024
    static let interactiveDimensionStep: CGFloat = 256

    /// 캔버스에 실제로 필요한 픽셀 수(긴 변, 디바이스 px)에 맞춘 인터랙티브 프록시 치수.
    /// 표시 픽셀 이상(업스케일 없음)이면서 스텝 양자화로 창 크기 미세 변화에 캐시가 유지된다.
    /// 상한은 정착 패스와 동일(fullMaxDimension) — 두 패스가 같은 치수면 스왑이 완전히 무변화다.
    static func interactiveProxyDimension(displayTargetPixels: CGFloat) -> CGFloat {
        guard displayTargetPixels > 0 else { return interactiveMaxDimension }
        let quantized = (displayTargetPixels / interactiveDimensionStep).rounded(.up) * interactiveDimensionStep
        return min(max(quantized, interactiveMinDimension), fullMaxDimension)
    }
    static let thumbnailMaxDimension: CGFloat = 360
    // 공유 렌더 컨텍스트는 Metal command queue 로 만든다. 단일 큐로 GPU 작업이 정렬돼, 빠른 반복
    // 렌더에서 "GPU 쓰기 완료 전에 결과를 읽어 빈/검은 프레임이 나오는" 동기화 버블을 없앤다
    // (Apple WWDC 권장: contextWithMTLCommandQueue). 디바이스가 없으면 기존 GPU 옵션으로 폴백.
    static let metalDevice = MTLCreateSystemDefaultDevice()
    static let metalQueue = metalDevice?.makeCommandQueue()
    static let sharedRenderContext: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ]
        if let queue = metalQueue {
            return CIContext(mtlCommandQueue: queue, options: options)
        }
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }()
    static let linearRawProxyContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
    ])
    static let srgbRawProxyContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])


}
