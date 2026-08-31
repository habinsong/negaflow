import Chromabase
import CoreImage
import Foundation

// MARK: - 컬러 프로세스 진단 명령
//
// Windows 의 `--auto-base-probe` / `--rescue-probe` 와 같은 항목을 같은 이름으로 낸다.
// 스캐너 TIFF 가 아니면 표준 디코더(RAW/DNG 포함)로 떨어지므로 카메라 스캔 원본도 그대로 연다
// — 이것이 없으면 카메라 스캔 보고를 한 발짝도 못 좁힌다.
extension CLI {
    func autoBaseProbe() async throws {
        let (image, filmType) = try probeInput()
        guard let report = ColorProcessProbe.autoBase(for: image, filmType: filmType) else {
            fail("auto base estimation failed", code: "auto_base_failed")
        }
        print("""
        {"status":"ok","operation":"auto_base_probe"\
        ,"width":\(report.width),"height":\(report.height)\
        ,"film":"\(filmType.rawValue)"\
        ,"source":"\(report.source)"\
        ,"dmin":\(json(report.dmin))\
        ,"brighterThanBase":\(fmt(report.brighterThanBase))\
        ,"rebateRescued":\(report.rebateRescued)\
        ,"method":"\(report.method ?? "none")"\
        ,"evidenceScore":\(fmt(report.evidenceScore ?? 0))\
        ,"sampledPixelCount":\(report.sampledPixelCount ?? 0)\
        ,"anomalies":[\(report.anomalies.map { "\"\($0)\"" }.joined(separator: ","))]\
        ,"microseconds":\(report.microseconds)}
        """)
    }

    func rescueProbe() async throws {
        let (image, filmType) = try probeInput()
        // 베이스를 손으로 넣어 현상 — "어두운 게 베이스 탓인가" 가 그 자리에서 갈린다.
        let override = ProcessInfo.processInfo.environment["NEGA_PROBE_DMIN"]
            .flatMap { text -> SIMD3<Double>? in
                let parts = text.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 3, parts.allSatisfy({ $0 > 0 }) else { return nil }
                return SIMD3(parts[0], parts[1], parts[2])
            }
        guard let report = ColorProcessProbe.rescue(
            for: image, filmType: filmType, dminOverride: override
        ) else {
            fail("rescue probe failed", code: "rescue_probe_failed")
        }
        print("""
        {"status":"ok","operation":"rescue_probe"\
        ,"width":\(report.width),"height":\(report.height)\
        ,"dmin":\(json(report.dmin))\
        ,"dmaxNormalized":\(json(report.dmaxNormalized))\
        ,"applied":\(report.applied)\
        ,"eligibleBands":\(report.eligibleBands)\
        ,"coveredTiles":\(report.coveredTiles)\
        ,"trainingSamples":\(report.trainingSamples)\
        ,"holdoutSamples":\(report.holdoutSamples)\
        ,"spreadBefore":\(fmt(report.spreadBefore))\
        ,"spreadAfter":\(fmt(report.spreadAfter))\
        ,"meanBefore":\(json(report.meanBefore))\
        ,"meanAfter":\(json(report.meanAfter))}
        """)
    }

    /// `<원본> [bw]` — 앱과 같은 디코드 경로를 탄다.
    private func probeInput() throws -> (CIImage, FilmType) {
        let rest = Array(args.dropFirst(2))
        guard let path = rest.first else {
            fail("usage: negaflow \(args.count > 1 ? args[1] : "probe") <image> [bw|positive]")
        }
        let filmType: FilmType
        switch rest.dropFirst().first {
        case "bw": filmType = .bwNegative
        case .some(let other): fail("unknown film argument: \(other)")
        case nil: filmType = .colorNegative
        }
        let url = URL(fileURLWithPath: path)
        let engine = ChromabaseEngine()
        guard let image = engine.loadScannerImage(url) ?? engine.loadImportedImage(url) else {
            throw ChromabaseError.loadFailed(url.path)
        }
        return (image, filmType)
    }

    private func fmt(_ value: Double) -> String { String(format: "%.6f", value) }

    private func json(_ value: SIMD3<Double>) -> String {
        "[\(fmt(value.x)),\(fmt(value.y)),\(fmt(value.z))]"
    }
}
