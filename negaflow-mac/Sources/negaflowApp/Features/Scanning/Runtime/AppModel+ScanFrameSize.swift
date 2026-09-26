import Chromabase
import Foundation

/// 프레임 규격 선택지. 목록의 규격 하나이거나, 목록에 없는 필름용 수동 비율이다.
enum ScanFrameFormatChoice: Hashable {
    case preset(FilmFrameFormat)
    case custom
}

extension AppModel {
    /// 배치·비율 맞춤·시뮬레이터가 쓰는 치수. 수동 비율이면 그 비율을 기억해 둔 필름 폭에
    /// 맞춰 세운다. 비율 맞춤은 비율만 보므로 사용자가 그린 크기는 그대로 둔다.
    var scanFrameSize: FilmFrameSize {
        if scanUsesCustomFrameSize, let scanCustomFrameRatio {
            return FilmFrameSize(ratio: scanCustomFrameRatio, acrossMM: scanCustomFrameAcrossMM)
        }
        return FilmFrameSize(scanFrameFormat)
    }

    /// 자동 검출이 대어 볼 크기. 규격은 하나, 수동 비율은 스캐너 영역에 들어가는 필름 폭마다 하나.
    var scanFrameSizeCandidates: [FilmFrameSize] {
        guard scanUsesCustomFrameSize, let scanCustomFrameRatio else {
            return [FilmFrameSize(scanFrameFormat)]
        }
        let fitting = scanCustomFrameRatio.candidateSizes.filter(scanFrameFits)
        return fitting.isEmpty ? [scanFrameSize] : fitting
    }

    var scanFrameFormatChoice: ScanFrameFormatChoice {
        scanUsesCustomFrameSize ? .custom : .preset(scanFrameFormat)
    }

    func selectScanFrameFormatChoice(_ choice: ScanFrameFormatChoice) async {
        switch choice {
        case .preset(let format): await selectScanFrameFormat(format)
        case .custom: await selectCustomScanFrameSize()
        }
    }

    /// 수동 비율로 바꾼다. 처음이면 지금 고른 규격의 비율로 채워 거기서 고치게 한다.
    func selectCustomScanFrameSize() async {
        guard !isScanning,
              !scanUsesCustomFrameSize,
              !availableScanFrameFormats.isEmpty else { return }
        if scanCustomFrameRatio == nil {
            scanCustomFrameRatio = FilmFrameRatio(
                width: scanFrameFormat.stripWidthMM,
                height: scanFrameFormat.stripHeightMM
            )
            scanCustomFrameAcrossMM = scanFrameFormat.is35mm
                ? FilmFrameRatio.candidateAcrossMM[0]
                : FilmFrameRatio.candidateAcrossMM[1]
        }
        scanUsesCustomFrameSize = true
        await applyScanFrameSizeChange()
    }

    /// 수동 비율 값을 바꾼다. 비율로 쓸 수 없거나 어떤 필름 폭으로도 스캐너 영역에 들어가지
    /// 않으면 받지 않고 `false`.
    @discardableResult
    func updateScanCustomFrameRatio(width: Double, height: Double) async -> Bool {
        guard !isScanning,
              let ratio = FilmFrameRatio(width: width, height: height),
              let fittingAcross = fittingAcrossMM(for: ratio) else { return false }
        guard ratio != scanCustomFrameRatio else { return true }
        scanCustomFrameRatio = ratio
        scanCustomFrameAcrossMM = fittingAcross
        if scanUsesCustomFrameSize {
            await applyScanFrameSizeChange()
        }
        return true
    }

    /// 지금 쓰던 필름 폭이 들어가면 그대로, 아니면 들어가는 첫 필름 폭.
    private func fittingAcrossMM(for ratio: FilmFrameRatio) -> Double? {
        let fitting = ratio.candidateSizes.filter(scanFrameFits).map(\.stripHeightMM)
        return fitting.contains(scanCustomFrameAcrossMM) ? scanCustomFrameAcrossMM : fitting.first
    }

    private func scanFrameFits(_ frameSize: FilmFrameSize) -> Bool {
        guard let maximum = hardwareScanAreaBounds?.maximum else { return false }
        return Self.frame(frameSize, fitsIn: maximum)
    }
}
