import CoreImage
import CoreGraphics
import Foundation

// 과거의 SP 타겟 그레이드(ScannerPrintGrade / ScannerOutputGrade)는 실패해 제거했다.
// main 타겟이 쓰는 MainTargetGrade만 남긴다. SP는 main 출력과 SP-3000 레퍼런스를
// 비교(LUT_target)해 처음부터 다시 설계할 예정.
enum MainTargetGrade {
    static func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "mainTargetGrade") else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }
}
