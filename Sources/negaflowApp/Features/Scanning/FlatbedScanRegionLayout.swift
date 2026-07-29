import Chromabase
import CoreGraphics
import Foundation
import ScannerKit

/// 버튼/단축키로 프레임을 추가할 때 놓을 자리를 정한다.
///
/// 규격 치수(mm)는 스트립을 가로로 놓았을 때 기준이라 그대로 쓰면 필름을 세로로 얹은 평판에서
/// 항상 90° 틀어진 프레임이 나온다. 홀더는 프레임이 가장 많이 들어가는 방향, 즉 스캔 영역의
/// 긴 축을 따라 놓이므로 프레임 진행 축도 그 축을 따른다. 이미 놓인 프레임이 있으면 그
/// 방향과 크기를 이어받아 다음 칸에 붙인다.
enum FlatbedScanRegionLayout {
    /// 프레임 사이 간격의 공칭값. 35mm 필름의 프레임 간격이 대략 이 정도다.
    static let frameGapMM: Double = 2

    static func proposedRect(
        existing: [CGRect],
        frameFormat: FilmFrameFormat,
        previewArea: ScanArea
    ) -> CGRect? {
        guard previewArea.widthMM.isFinite,
              previewArea.heightMM.isFinite,
              previewArea.widthMM > 0,
              previewArea.heightMM > 0 else { return nil }
        let gap = CGSize(
            width: frameGapMM / previewArea.widthMM,
            height: frameGapMM / previewArea.heightMM
        )
        guard let last = existing.last, let first = existing.first else {
            return centered(size: firstFrameSize(
                frameFormat: frameFormat,
                previewArea: previewArea
            ))
        }
        // 프레임의 긴 축(mm)이 스트립 진행 축이다. 정사각 프레임은 가로로 진행시킨다.
        let advancesAlongX = last.width * previewArea.widthMM
            >= last.height * previewArea.heightMM
        let next = advancesAlongX
            ? last.offsetBy(dx: last.width + gap.width, dy: 0)
            : last.offsetBy(dx: 0, dy: last.height + gap.height)
        if fits(next) { return next }

        // 스트립 끝. 다음 줄 첫 칸(첫 프레임의 진행축 위치)으로 넘어간다.
        let wrapped = advancesAlongX
            ? CGRect(
                x: first.minX,
                y: last.maxY + gap.height,
                width: last.width,
                height: last.height
            )
            : CGRect(
                x: last.maxX + gap.width,
                y: first.minY,
                width: last.width,
                height: last.height
            )
        return fits(wrapped) ? wrapped : centered(size: last.size)
    }

    /// 손으로 그리거나 핸들로 조정한 사각형을 선택한 규격의 비율에 맞춘다. 눈으로는 6×7인지
    /// 6×9인지 구분할 수 없으므로, 크기를 바꾸는 조작마다 비율을 규격으로 되돌려 준다.
    ///
    /// 비율은 화면 픽셀이 아니라 물리 치수(mm)로 따진다. 방향은 사용자가 그린 형태에 가까운
    /// 쪽(가로/세로)을 쓰고, 움직이지 않은 변은 그대로 두며, 조작하지 않은 축은 중심을 지킨다.
    static func snappedToFrameAspect(
        _ rect: CGRect,
        anchoredTo previous: CGRect,
        frameFormat: FilmFrameFormat,
        previewArea: ScanArea,
        epsilon: CGFloat = 0.000_1
    ) -> CGRect {
        guard previewArea.widthMM.isFinite,
              previewArea.heightMM.isFinite,
              previewArea.widthMM > 0,
              previewArea.heightMM > 0,
              rect.width > 0,
              rect.height > 0 else { return rect }
        let movedX = abs(rect.minX - previous.minX) > epsilon
            || abs(rect.maxX - previous.maxX) > epsilon
        let movedY = abs(rect.minY - previous.minY) > epsilon
            || abs(rect.maxY - previous.maxY) > epsilon
        // 크기를 건드리지 않은 조작(이동)은 비율에 손대지 않는다.
        guard movedX || movedY else { return rect }

        let widthMM = Double(rect.width) * previewArea.widthMM
        let heightMM = Double(rect.height) * previewArea.heightMM
        let aspect = widthMM / heightMM
        guard aspect.isFinite, aspect > 0 else { return rect }
        let target = frameFormat.frameAspectCandidates.min {
            abs(log($0) - log(aspect)) < abs(log($1) - log(aspect))
        } ?? aspect
        let width = CGFloat(heightMM * target / previewArea.widthMM)
        let height = CGFloat(widthMM / target / previewArea.heightMM)

        let size: CGSize
        if movedX != movedY {
            // 한 변만 끈 경우: 끈 축이 크기를 정하고 반대 축이 따라온다.
            size = movedX
                ? CGSize(width: rect.width, height: height)
                : CGSize(width: width, height: rect.height)
        } else {
            // 모서리를 끌거나 새로 그린 경우: 짧은 축에 맞춰 그린 영역 밖으로 커지지 않게 한다.
            size = aspect > target
                ? CGSize(width: width, height: rect.height)
                : CGSize(width: rect.width, height: height)
        }
        return CGRect(
            x: movedX
                ? anchoredOrigin(
                    rect.minX,
                    rect.maxX,
                    previous: previous.minX,
                    previousMaximum: previous.maxX,
                    extent: size.width,
                    epsilon: epsilon
                )
                : rect.midX - size.width / 2,
            y: movedY
                ? anchoredOrigin(
                    rect.minY,
                    rect.maxY,
                    previous: previous.minY,
                    previousMaximum: previous.maxY,
                    extent: size.height,
                    epsilon: epsilon
                )
                : rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 움직이지 않은 변을 고정한다. 양쪽 다 움직였으면 중심을 지킨다.
    private static func anchoredOrigin(
        _ minimum: CGFloat,
        _ maximum: CGFloat,
        previous minimumPrevious: CGFloat,
        previousMaximum: CGFloat,
        extent: CGFloat,
        epsilon: CGFloat
    ) -> CGFloat {
        if abs(minimum - minimumPrevious) <= epsilon { return minimum }
        if abs(maximum - previousMaximum) <= epsilon { return maximum - extent }
        return (minimum + maximum) / 2 - extent / 2
    }

    private static func firstFrameSize(
        frameFormat: FilmFrameFormat,
        previewArea: ScanArea
    ) -> CGSize {
        let stripAdvancesAlongY = previewArea.heightMM > previewArea.widthMM
        let widthMM = stripAdvancesAlongY
            ? frameFormat.stripHeightMM
            : frameFormat.stripWidthMM
        let heightMM = stripAdvancesAlongY
            ? frameFormat.stripWidthMM
            : frameFormat.stripHeightMM
        return CGSize(
            width: min(max(widthMM / previewArea.widthMM, 0.02), 1),
            height: min(max(heightMM / previewArea.heightMM, 0.02), 1)
        )
    }

    private static func centered(size: CGSize) -> CGRect {
        CGRect(
            x: (1 - size.width) / 2,
            y: (1 - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func fits(_ rect: CGRect) -> Bool {
        rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 1 && rect.maxY <= 1
    }
}
