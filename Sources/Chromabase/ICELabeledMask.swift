import Foundation

// 컴포넌트(연결요소) 라벨맵 — 반자동 Region ICE 전용.
//
// 브러시 ICE는 검출 마스크(RGBA8)를 바로 복원에 쓴다(ICEComponentMask.build). Region ICE는
// 사용자가 개별 결함을 클릭으로 제외해야 하므로, 마스크를 "라벨링된 컴포넌트 목록"으로 들고
// 있어야 한다. 게이트(면적/aspect/길이) 통과 판정은 ICEComponentMask 와 동일 로직을 공유한다
// (ICEComponentMask.buildLabeled). 여기서는 결과 타입과 좌표 조회만 정의한다.

public struct ICEComponent: Sendable {
    public enum Kind: Sendable, Equatable { case dust, scratch }
    public let id: Int32
    public let kind: Kind
    /// 검출 해상도(라벨맵) 로컬 픽셀 인덱스. 게이트 통과 원픽셀(먼지 hole-fill·dilate 전).
    public let pixels: [Int]
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int

    public var pixelCount: Int { pixels.count }
}

public struct ICELabelField: Sendable {
    public let width: Int
    public let height: Int
    /// 픽셀별 컴포넌트 id(-1 = 배경). 클릭 위치 → 컴포넌트 조회에 쓴다.
    public let labels: [Int32]
    public let components: [ICEComponent]

    public init(width: Int, height: Int, labels: [Int32], components: [ICEComponent]) {
        self.width = width
        self.height = height
        self.labels = labels
        self.components = components
    }

    public var isEmpty: Bool { components.isEmpty }
    public var allIDs: Set<Int32> { Set(components.map { $0.id }) }

    /// (x,y)에 정확히 놓인 컴포넌트 id. 배경이면 nil.
    public func componentID(atX x: Int, y: Int) -> Int32? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let l = labels[y * width + x]
        return l >= 0 ? l : nil
    }

    /// (x,y) 정확 위치 우선, 없으면 반경 내 가장 가까운 컴포넌트 픽셀의 id. 얇은 스크래치 등
    /// 클릭 타깃이 작을 때 히트테스트 관용도를 준다(맨해튼 거리 확장 탐색).
    public func nearestComponentID(atX x: Int, y: Int, radius: Int) -> Int32? {
        if let exact = componentID(atX: x, y: y) { return exact }
        guard radius > 0 else { return nil }
        for r in 1...radius {
            var best: Int32?
            // 반경 r 정사각 링만 검사(안쪽 링은 이전 r 에서 이미 봄).
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    if let id = componentID(atX: x + dx, y: y + dy) { best = id }
                }
            }
            if let best { return best }
        }
        return nil
    }
}
