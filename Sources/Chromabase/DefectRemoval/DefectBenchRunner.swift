import CoreImage
import Foundation

// MARK: - GrainMend RGB 자동 골든셋 벤치마크 러너
//
// 실제 스캔 골든셋에 대한 before/after·diff·100% crop·수치 리포트를 산출한다. 판정(QA)은
// 사람이 한다 — 러너는 자동 검출/복원을 돌리고 비교 아티팩트와 측정치를 만드는 도구다.
// CLI(`negaflow defect-bench`)가 이걸 감싼다. 테스트는 합성 이미지로만 이 러너를 검증한다.

/// 한 이미지의 벤치 결과(리포트 항목).
public struct DefectBenchEntry: Codable, Sendable {
    public let imageName: String
    public let width: Int
    public let height: Int
    public let sensitivity: Double
    public let detectMilliseconds: Double
    public let repairMilliseconds: Double
    /// DefectClass.rawValue → 개수.
    public let defectCounts: [String: Int]
    public let defectTotal: Int
    public let meanConfidence: Double
    /// 팽창 전 검출 컴포넌트가 차지하는 원픽셀 비율. 자동 모드의 과검출 밀도를 감시한다.
    public let candidatePixelFraction: Double
    /// 자동 모드가 오검출 위험이 높다고 표시했는지 여부(경고 전용 — 복원은 그대로 적용된다).
    public let automaticFalsePositiveRisk: Bool
    /// |Δ| > 2/255 로 바뀐 픽셀 수/비율(과잉 수정 감시용).
    public let changedPixelCount: Int
    public let changedPixelFraction: Double
    /// 바뀐 픽셀의 평균 |Δ| (0~1).
    public let meanChangedDelta: Double
    public let artifacts: [String]
    public let referenceMetrics: DefectBenchReferenceMetrics?
}

public enum DefectBenchRunner {
    /// 파일 하나를 벤치한다. 산출물(before/after/diff/mask/crop PNG)은 outputDir 에 쓴다.
    public static func run(imageURL: URL, referenceURL: URL? = nil, outputDir: URL,
                           writeArtifacts: Bool = true,
                           sensitivity: Double = 0.7,
                           cropCount: Int = 8, cropSize: Int = 256) throws -> DefectBenchEntry {
        guard let image = ImageLoader.load(imageURL) else {
            throw ChromabaseError.writeFailed("이미지를 열 수 없습니다: \(imageURL.path)")
        }
        let reference = try referenceURL.map { url in
            guard let image = ImageLoader.load(url) else {
                throw ChromabaseError.writeFailed("골든셋 정답 이미지를 열 수 없습니다: \(url.path)")
            }
            return image
        }
        let name = imageURL.deletingPathExtension().lastPathComponent
        return try run(image: image, name: name, outputDir: outputDir,
                       reference: reference,
                       referenceName: referenceURL?.lastPathComponent,
                       writeArtifacts: writeArtifacts,
                       sensitivity: sensitivity, cropCount: cropCount, cropSize: cropSize)
    }

    /// CIImage 를 벤치한다(테스트가 합성 이미지로 직접 호출하는 진입점).
    public static func run(image: CIImage, name: String, outputDir: URL,
                           reference: CIImage? = nil, referenceName: String? = nil,
                           writeArtifacts: Bool = true,
                           sensitivity: Double = 0.7,
                           cropCount: Int = 8, cropSize: Int = 256) throws -> DefectBenchEntry {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let extent = image.extent.integral
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        guard w > 4, h > 4 else { throw ChromabaseError.writeFailed("이미지가 너무 작습니다: \(name)") }

        // 영역 결함 제거 슬라이더 전체 범위(0.7~6.0)를 detector가 정의한 0~1 민감도로 매핑한다.
        let s = max(0, min(1, (sensitivity - 0.7) / (6.0 - 0.7)))
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: s,
                                           scratchSensitivity: min(1, s + 0.1), protectDetail: 0.6)

        let detectStart = DispatchTime.now()
        let field = SoftwareDefectRemoval.detectComponents(
            in: image,
            roi: extent,
            parameters: params,
            wholeFrameAuto: true
        )
        let detectMS = Double(DispatchTime.now().uptimeNanoseconds - detectStart.uptimeNanoseconds) / 1e6

        let repairStart = DispatchTime.now()
        let repaired = field.isEmpty ? image
            : (SoftwareDefectRemoval.repairComponents(image: image, roi: extent, field: field, excluded: []) ?? image)
        let repairMS = Double(DispatchTime.now().uptimeNanoseconds - repairStart.uptimeNanoseconds) / 1e6

        let before = DefectBenchArtifacts.renderRGBA8(image, extent: extent)
        let after = DefectBenchArtifacts.renderRGBA8(repaired, extent: extent)
        let (diff, changed, changedDeltaSum) = DefectBenchArtifacts.diffHeatmap(before: before, after: after,
                                                                             width: w, height: h)
        let referenceMetrics = try reference.map { reference in
            let referenceExtent = reference.extent.integral
            guard Int(referenceExtent.width.rounded()) == w,
                  Int(referenceExtent.height.rounded()) == h
            else {
                throw ChromabaseError.writeFailed("골든셋 정답 이미지 크기가 일치하지 않습니다: \(referenceName ?? name)")
            }
            return try DefectBenchReferenceEvaluator.evaluate(
                before: before,
                after: after,
                reference: DefectBenchArtifacts.renderRGBA8(reference, extent: referenceExtent),
                width: w,
                height: h,
                referenceName: referenceName ?? "reference"
            )
        }

        var artifacts: [String] = []
        func write(_ bytes: [UInt8], _ suffix: String) throws {
            let file = "\(name)-\(suffix).png"
            try DefectBenchArtifacts.writePNG(bytes, width: w, height: h,
                                           to: outputDir.appendingPathComponent(file))
            artifacts.append(file)
        }
        if writeArtifacts {
            try write(before, "before")
            try write(after, "after")
            try write(diff, "diff")
            try write(
                DefectBenchArtifacts.maskOverlay(on: before, field: field, width: w, height: h),
                "mask"
            )
            artifacts += DefectBenchArtifacts.writeCrops(
                field: field,
                before: before,
                after: after,
                diff: diff,
                width: w,
                height: h,
                name: name,
                outputDir: outputDir,
                cropCount: cropCount,
                cropSize: cropSize
            )
        }

        var counts: [String: Int] = [:]
        var confidenceSum = 0.0
        for comp in field.components {
            counts[comp.classification.rawValue, default: 0] += 1
            confidenceSum += comp.confidence
        }
        let candidatePixelCount = field.components.reduce(0) { $0 + $1.pixelCount }
        return DefectBenchEntry(
            imageName: name, width: w, height: h, sensitivity: sensitivity,
            detectMilliseconds: detectMS, repairMilliseconds: repairMS,
            defectCounts: counts, defectTotal: field.components.count,
            meanConfidence: field.components.isEmpty ? 0 : confidenceSum / Double(field.components.count),
            candidatePixelFraction: field.automaticCandidatePixelFraction
                ?? Double(candidatePixelCount) / Double(w * h),
            automaticFalsePositiveRisk: field.automaticFalsePositiveRisk,
            changedPixelCount: changed,
            changedPixelFraction: Double(changed) / Double(w * h),
            meanChangedDelta: changed > 0 ? changedDeltaSum / Double(changed) : 0,
            artifacts: artifacts,
            referenceMetrics: referenceMetrics
        )
    }
}
