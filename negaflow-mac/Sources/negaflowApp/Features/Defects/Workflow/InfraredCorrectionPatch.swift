import Chromabase
import CoreImage
import CoreGraphics
import Foundation

// MARK: - IR 감쇠 보정 패치
//
// 먼지·스크래치는 빛을 **부분적으로** 가린다. 실측(GT-X900, 컬러 네거티브 18컷)에서 결함
// 하나를 스택 평균하면 가시광은 중심에서 7% 떨어지고 반경 20px 까지 옅게 끌렸다 — 도려내
// 메우는 방식은 IR 이 알려 주는 좁은 심만 처리하고 그 자락을 그대로 남긴다(실측 제거율 37.6%).
// 그래서 가려진 만큼 되돌린다: raw ÷ (1 − 감쇠).
//
// 되돌릴 수 있는 한도는 있다. 빛이 거의 다 막힌 자리는 나눗셈이 잡음만 키우므로, 이득 상한
// (2배)에 걸리는 심만 기존 복원 코어가 메운다. 메우기의 문맥은 **이미 보정된 이미지**라,
// 심 둘레의 부분 폐색 픽셀이 성한 값으로 들어간다.
func infraredPatch(img: CIImage, cluster: InfraredDefectRemoval.Cluster) -> DefectPatch? {
    guard let attenuationData = cluster.attenuationR16 else { return nil }
    let width = cluster.width
    let height = cluster.height
    let count = width * height
    guard width > 0, height > 0, attenuationData.count == count * 2,
          Int(cluster.roiYup.width) == width, Int(cluster.roiYup.height) == height,
          cluster.roiYup.intersection(img.extent) == cluster.roiYup else { return nil }

    // 감쇠(16bit, 비트맵 행 순서 y-down) 디코드 + 보정이 실제로 닿는 범위.
    var attenuation = [Float](repeating: 0, count: count)
    var minX = width, maxX = -1, minY = height, maxY = -1
    attenuationData.withUnsafeBytes { raw in
        let values = raw.bindMemory(to: UInt16.self)
        for index in 0..<count {
            let value = Float(values[index]) / 65535
            attenuation[index] = value
            guard value > 0 else { continue }
            let x = index % width, y = index / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    // ROI 를 float 로 받아 이득을 곱한다. CIContext 는 bounds 의 위쪽 행부터 채우므로
    // 버퍼 행 순서가 감쇠 맵(y-down)과 같다.
    var buffer = [Float](repeating: 0, count: count * 4)
    let rendered: Bool = buffer.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return false }
        cleanedRawContext.render(img, toBitmap: base, rowBytes: width * 16,
                                 bounds: cluster.roiYup, format: .RGBAf,
                                 colorSpace: linearColorSpace)
        return true
    }
    guard rendered else { return nil }
    // 이득 상한(AGC): 빛의 절반 이상이 남아 있을 때만 나눗셈으로 되돌린다.
    let transmittanceFloor: Float = 0.5
    for index in 0..<count {
        let gain = 1 / max(1 - attenuation[index], transmittanceFloor)
        guard gain > 1 else { continue }
        let offset = index * 4
        buffer[offset] *= gain
        buffer[offset + 1] *= gain
        buffer[offset + 2] *= gain
    }

    let correctedTile = buffer.withUnsafeBufferPointer { pointer -> CIImage? in
        CIImage(bitmapData: Data(buffer: pointer),
                bytesPerRow: width * 16,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linearColorSpace)
    }
    guard let correctedTile else { return nil }
    let corrected = correctedTile
        .transformed(by: CGAffineTransform(translationX: cluster.roiYup.minX,
                                           y: cluster.roiYup.minY))
        .composited(over: img)

    // 완전 폐색 심이 있으면 보정된 이미지 위에서 메운다.
    var result = corrected
    if let coreBounds = infraredCoreBounds(cluster.maskRGBA8, width: width, height: height) {
        if let healed = SoftwareDefectRemoval.repair(image: corrected, roi: cluster.roiYup,
                                                     maskRGBA8: cluster.maskRGBA8,
                                                     width: width, height: height) {
            result = healed
        }
        minX = min(minX, Int(coreBounds.minX))
        maxX = max(maxX, Int(coreBounds.maxX) - 1)
        minY = min(minY, Int(coreBounds.minY))
        maxY = max(maxY, Int(coreBounds.maxY) - 1)
    }

    // y-down 로컬 bbox → y-up 로컬 rect → ROI 로 평행이동.
    let local = CGRect(x: CGFloat(minX),
                       y: CGFloat(height - maxY - 1),
                       width: CGFloat(maxX - minX + 1),
                       height: CGFloat(maxY - minY + 1))
    let rect = local
        .offsetBy(dx: cluster.roiYup.minX, dy: cluster.roiYup.minY)
        .integral
        .intersection(cluster.roiYup.integral)
        .intersection(img.extent)
    guard rect.width >= 1, rect.height >= 1,
          let patch = cleanedRawContext.createCGImage(result, from: rect,
                                                      format: .RGBA16,
                                                      colorSpace: linearColorSpace)
    else { return nil }
    return DefectPatch(rect: rect, image: patch)
}

/// 코어 마스크(RGBA8, y-down)에서 흰 픽셀의 경계(y-down 로컬). 없으면 nil.
private func infraredCoreBounds(_ mask: Data, width: Int, height: Int) -> CGRect? {
    guard mask.count == width * height * 4 else { return nil }
    var minX = width, minY = height, maxX = -1, maxY = -1
    mask.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where bytes[(row + x) * 4] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
}
