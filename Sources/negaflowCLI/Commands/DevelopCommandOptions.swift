import Foundation
import Chromabase

struct DevelopOptionsError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// `negaflow develop` 인자 파서(순수 함수). 프로세스 종료(exit)는 호출측(CLI.fail)만 한다.
///
/// 기존 이중 수동 루프를 대체한다. 유효 입력의 의미는 동일하고, 다음만 달라진다:
///   • 알 수 없는 `--옵션`/떠돌이 토큰 → 조용히 무시하는 대신 에러.
///   • 숫자 옵션의 파싱 실패 → 0 으로 바꾸는 대신 에러.
///   • `--film-type` 오타 → 추측값 폴백 대신 에러.
struct DevelopCommandOptions: Equatable {
    var inputPath: String
    var outputPath: String
    var lookName = "neutral"
    var scannerProfileID: String?
    var filmType: FilmType?
    var scannerRaw = false
    var defects: Double = 0
    var developTarget: DevelopTarget = .main
    var outputICCPath: String?
    var expectedOutputICCSHA256: String?
    var defectMaskPath: String?
    var defectOverlayPath: String?
    var toneOverrides: [ToneParameter: Double] = [:]

    enum ToneParameter: String, CaseIterable {
        case exposure, contrast, highlight, shadow, whites, blacks, density
        case noiseReduction, noiseReductionLuma, noiseReductionChroma
        case noiseReductionDarkTone, noiseReductionDetail, noiseReductionGrainProtect
    }

    /// develop 하위 인자([in, out, 옵션...])를 파싱한다.
    static func parse(_ arguments: [String]) -> Result<DevelopCommandOptions, DevelopOptionsError> {
        guard arguments.count >= 2 else {
            return .failure(DevelopOptionsError(
                message: "usage: negaflow develop <in> <out> [--look name] [--scanner-profile id] [--film-type T] [--positive] [--raw]"
            ))
        }
        var options = DevelopCommandOptions(
            inputPath: arguments[0],
            outputPath: arguments[1]
        )
        let toneFlags: [String: ToneParameter] = [
            "--exposure": .exposure,
            "--contrast": .contrast,
            "--highlights": .highlight, "--highlight": .highlight,
            "--shadows": .shadow, "--shadow": .shadow,
            "--whites": .whites,
            "--blacks": .blacks,
            "--density": .density,
            "--noise-reduction": .noiseReduction, "--nr": .noiseReduction,
            "--nr-luma": .noiseReductionLuma,
            "--nr-chroma": .noiseReductionChroma,
            "--nr-dark": .noiseReductionDarkTone,
            "--nr-detail": .noiseReductionDetail,
            "--nr-grain": .noiseReductionGrainProtect,
        ]

        var index = 2
        func requiredValue(for flag: String) -> Result<String, DevelopOptionsError> {
            guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                return .failure(DevelopOptionsError(message: "\(flag) requires a value"))
            }
            return .success(arguments[index + 1])
        }
        func requiredDouble(for flag: String) -> Result<Double, DevelopOptionsError> {
            switch requiredValue(for: flag) {
            case .failure(let message):
                return .failure(message)
            case .success(let raw):
                guard let value = Double(raw), value.isFinite else {
                    return .failure(DevelopOptionsError(message: "\(flag) requires a number, got: \(raw)"))
                }
                return .success(value)
            }
        }

        while index < arguments.count {
            let flag = arguments[index]
            if let tone = toneFlags[flag] {
                switch requiredDouble(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value):
                    options.toneOverrides[tone] = value
                    index += 2
                }
                continue
            }
            switch flag {
            case "--look":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value): options.lookName = value; index += 2
                }
            case "--scanner-profile":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value): options.scannerProfileID = value; index += 2
                }
            case "--film-type":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value):
                    guard let filmType = FilmType(rawValue: value) else {
                        let values = FilmType.allCases.map(\.rawValue)
                            .joined(separator: ", ")
                        return .failure(DevelopOptionsError(message: "--film-type requires one of: \(values), got: \(value)"))
                    }
                    options.filmType = filmType
                    index += 2
                }
            case "--positive":
                options.filmType = .colorPositive
                index += 1
            case "--bw-positive":
                options.filmType = .bwPositive
                index += 1
            case "--raw":
                options.scannerRaw = true
                index += 1
            case "--target":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value):
                    guard !value.hasPrefix("--"),
                          let target = DevelopTarget(rawValue: value) else {
                        let values = DevelopTarget.allCases.map(\.rawValue)
                            .joined(separator: ", ")
                        return .failure(DevelopOptionsError(message: "--target requires one of: \(values)"))
                    }
                    options.developTarget = target
                    index += 2
                }
            case "--output-icc":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value):
                    guard !value.hasPrefix("--") else {
                        return .failure(DevelopOptionsError(message: "--output-icc requires a path"))
                    }
                    options.outputICCPath = value
                    index += 2
                }
            case "--output-icc-sha256":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value):
                    guard !value.hasPrefix("--") else {
                        return .failure(DevelopOptionsError(message: "--output-icc-sha256 requires a hash"))
                    }
                    options.expectedOutputICCSHA256 = value
                    index += 2
                }
            case "--defects":
                // 값은 선택: 다음 토큰이 숫자면 소비, 아니면 기본 1.0.
                if index + 1 < arguments.count, let value = Double(arguments[index + 1]) {
                    options.defects = value
                    index += 2
                } else {
                    options.defects = 1.0
                    index += 1
                }
            case "--defect-mask":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value): options.defectMaskPath = value; index += 2
                }
            case "--defect-overlay":
                switch requiredValue(for: flag) {
                case .failure(let message): return .failure(message)
                case .success(let value): options.defectOverlayPath = value; index += 2
                }
            default:
                if flag.hasPrefix("--") {
                    return .failure(DevelopOptionsError(message: "unknown option: \(flag)"))
                }
                return .failure(DevelopOptionsError(message: "unexpected argument: \(flag)"))
            }
        }

        if options.developTarget == .print {
            guard options.outputICCPath != nil,
                  options.expectedOutputICCSHA256 != nil else {
                return .failure(DevelopOptionsError(message: "--target print requires --output-icc and --output-icc-sha256"))
            }
        } else if options.outputICCPath != nil || options.expectedOutputICCSHA256 != nil {
            return .failure(DevelopOptionsError(message: "--output-icc is only valid with --target print"))
        }
        return .success(options)
    }

    /// 톤 오버라이드를 DevelopParameters 에 적용한다(기존 두 번째 루프와 동일한 대입).
    func applyToneOverrides(to params: inout DevelopParameters) {
        for (tone, value) in toneOverrides {
            switch tone {
            case .exposure: params.exposure = value
            case .contrast: params.contrast = value
            case .highlight: params.highlight = value
            case .shadow: params.shadow = value
            case .whites: params.whites = value
            case .blacks: params.blacks = value
            case .density: params.density = value
            case .noiseReduction: params.noiseReduction = value
            case .noiseReductionLuma: params.noiseReductionLuma = value
            case .noiseReductionChroma: params.noiseReductionChroma = value
            case .noiseReductionDarkTone: params.noiseReductionDarkTone = value
            case .noiseReductionDetail: params.noiseReductionDetail = value
            case .noiseReductionGrainProtect: params.noiseReductionGrainProtect = value
            }
        }
    }
}
