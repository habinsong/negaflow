import Foundation

// 스크래치 방향 적분 응답의 **프레임 전역** 저해상도 맵.
//
// 연장 증거 판정(DefectStructureLineFilter)은 컴포넌트 끝점 바깥 수십 px 를 읽어야 하는데, 타일
// 검출 안에서는 그 구간이 halo 밖으로 나가 판정 불가가 되고 컴포넌트 자체도 타일 경계에서 잘린다.
// 그래서 타일 검출이 이미 계산해 둔 응답을 전역 좌표에 모아 두고, stitch 이후 프레임 전체에서
// 한 번에 판정한다(응답을 새로 계산하지 않으므로 검출 비용은 늘지 않는다).
//
// 저장은 2배 다운샘플 max-pooling 이다. 판정 대상이 "수십 px 이상 이어지는 선"이라 절반 해상도로
// 충분하고, max 를 쓰므로 1px 두께 선의 응답도 소실되지 않는다. 메모리는 원본의 1/4 이다.
struct DefectScratchResponseMap {
    /// 원본(검출 ROI) 좌표 → 맵 좌표 축소 배율.
    static let downsample = 2

    let width: Int
    let height: Int
    private(set) var values: [Float]

    /// 원본 ROI 크기로 빈 맵을 만든다.
    init(sourceWidth: Int, sourceHeight: Int) {
        width = max(1, (sourceWidth + Self.downsample - 1) / Self.downsample)
        height = max(1, (sourceHeight + Self.downsample - 1) / Self.downsample)
        values = [Float](repeating: 0, count: width * height)
    }

    /// 타일 응답을 전역 맵에 병합한다(겹치는 자리는 max).
    /// - tile: 타일 로컬 응답(tileWidth × tileHeight, y-down).
    /// - originX/originY: 타일 좌상단의 전역 ROI 좌표(y-down).
    mutating func merge(tile: [Float], tileWidth: Int, tileHeight: Int,
                        originX: Int, originY: Int) {
        guard tile.count == tileWidth * tileHeight else { return }
        let step = Self.downsample
        for y in 0..<tileHeight {
            let globalY = (originY + y) / step
            guard globalY >= 0, globalY < height else { continue }
            let rowBase = globalY * width
            let tileRow = y * tileWidth
            for x in 0..<tileWidth {
                let globalX = (originX + x) / step
                guard globalX >= 0, globalX < width else { continue }
                let value = tile[tileRow + x]
                let index = rowBase + globalX
                if value > values[index] { values[index] = value }
            }
        }
    }

    /// 전역 ROI 좌표(y-down)의 응답. 범위 밖이면 nil(=판정 불가).
    func value(atX x: Int, y: Int) -> Float? {
        let mx = x / Self.downsample, my = y / Self.downsample
        guard mx >= 0, mx < width, my >= 0, my < height else { return nil }
        return values[my * width + mx]
    }
}
