import CoreImage
import simd

// MARK: - DisplayGamutMap
//
// 작업 파이프라인은 확장범위(음수·1 초과) 값을 보존한다 — MAIN 플랫 마스터의 명부
// 관용도와 유채색을 비가역적으로 잃지 않기 위해서다(ChromabaseEngine+PostPipeline 참고).
// 대신 출력 경계(디스플레이·썸네일·JPEG/PNG/TIFF 내보내기)에서만, per-channel 하드 클립 대신
// luma 보존 hue-safe soft-clip(gamutSoftClip 커널 = toneSafeUnitRGB)으로 out-of-gamut 값을
// 그 경계의 색공간 [0,1] 안으로 접는다. DNG·원본 스캔 TIFF 는 접지 않는다.
//
// 반드시 soft-proof **이전**에 적용해야 한다: soft-proof(종이+블랙잉크)는 `input*scale + black`
// 형태의 선형 재매핑이라 [0,1] 입력만 종이 화이트(<1)로 압축한다. 확장 입력을 그대로 넣으면
// 확장값이 유지돼 8bit createCGImage 에서 하드 클립(전부 흰색)되고, 프루프가 원본과 구별되지
// 않는다. in-gamut([0,1]) 픽셀에 대해서는 toneSafeUnitRGB 가 항등이므로 일반 이미지는 불변이다.
public enum DisplayGamutMap {
    public static func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "gamutSoftClip")
        else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }

    /// 내보내기 경계의 접기. 프리뷰가 거치는 것과 같은 hue-safe soft-clip 을 **파일이
    /// 인코딩되는 색공간**의 선형 기본색에서 건다.
    ///
    /// 앞 판은 프리뷰만 접고 파일은 `createCGImage` 가 채널마다 잘랐다. 선형 (1.3, 0.9, 0.5)
    /// 화소가 프리뷰 (255, 249, 243), 파일 (255, 243, 188) 로 갈렸다. 작업 이미지는 그대로
    /// 확장값을 보존하고, 목적 색공간을 아는 이 경계에서만 접는다. 윈도우
    /// `convert_working_to_srgb_rows` 도 같은 자리에서 같은 식을 쓴다.
    public static func apply(to image: CIImage, encodedIn space: ExportColorSpace) -> CIImage {
        guard space != .sRGB else { return apply(to: image) }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "targetGamutSoftClip")
        else { return image }
        let forward = linearSRGB(to: space)
        let inverse = forward.inverse
        func row(_ matrix: simd_double3x3, _ index: Int) -> CIVector {
            CIVector(x: matrix[0][index], y: matrix[1][index], z: matrix[2][index], w: 0)
        }
        return kernel.apply(extent: extent, arguments: [
            image,
            row(forward, 0), row(forward, 1), row(forward, 2),
            row(inverse, 0), row(inverse, 1), row(inverse, 2),
        ])?.cropped(to: extent) ?? image
    }

    /// 선형 sRGB 기본색 → 목적 공간 선형 기본색. 세 공간 모두 D65 라 색순응 없이 기본색만
    /// 바꾼다(윈도우 `color::linear_srgb_to` 와 같은 구성).
    static func linearSRGB(to space: ExportColorSpace) -> simd_double3x3 {
        let srgb = rgbToXYZ(primaries(.sRGB))
        return rgbToXYZ(primaries(space)).inverse * srgb
    }

    private static func primaries(_ space: ExportColorSpace) -> [SIMD2<Double>] {
        switch space {
        case .sRGB:
            return [SIMD2(0.640, 0.330), SIMD2(0.300, 0.600), SIMD2(0.150, 0.060)]
        case .displayP3:
            return [SIMD2(0.680, 0.320), SIMD2(0.265, 0.690), SIMD2(0.150, 0.060)]
        case .adobeRGB:
            return [SIMD2(0.640, 0.330), SIMD2(0.210, 0.710), SIMD2(0.150, 0.060)]
        }
    }

    private static func rgbToXYZ(_ primaries: [SIMD2<Double>]) -> simd_double3x3 {
        func xyz(_ xy: SIMD2<Double>) -> SIMD3<Double> {
            SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y)
        }
        let chromaticities = simd_double3x3(columns: (
            xyz(primaries[0]), xyz(primaries[1]), xyz(primaries[2])
        ))
        let white = xyz(SIMD2(0.3127, 0.3290))
        let scale = chromaticities.inverse * white
        return simd_double3x3(columns: (
            chromaticities.columns.0 * scale.x,
            chromaticities.columns.1 * scale.y,
            chromaticities.columns.2 * scale.z
        ))
    }
}
