import Foundation

extension DefectComponentMask {
    static func buildLabeled(width: Int, height: Int,
                             dust: [Bool], scratch: [Bool],
                             scratchStrong: [Bool]? = nil,
                             dustStrong: [Bool]? = nil,
                             maxDustArea: Int, minScratchLength: Int,
                             minScratchAspect: Double = 2.5,
                             dustMaxAspect: Double = 4.0,
                             minThickDefect: Int = .max, maxThickDefect: Int = 0,
                             dustTrustedStrong: [Bool]? = nil,
                             microDustMinArea: Int = 1,
                             grainFieldSmallMax: Int = DefectComponentMask.grainFieldSmallMax,
                             rejectLineGrid: Bool = false,
                             scratchResponse: [Float]? = nil) -> DefectLabelField {
        var labels = [Int32](repeating: -1, count: width * height)
        var components: [DefectComponent] = []
        var nextID: Int32 = 0

        let dustComps = rawComponents(of: dust, width: width, height: height)
        let chunky = chunkyMap(dustComps, width: width, height: height)
        var acceptedDust: [RawComponent] = []
        for c in dustComps {
            // 히스테리시스: strong 코어가 하나라도 있어야 채택 — weak 프린지만으로 된 컴포넌트
            // (그레인/저대비 텍스처)는 버린다.
            let hasStrong = dustStrong.map { map in c.pixels.contains(where: { map[$0] }) } ?? true
            let hasTrustedEvidence = dustTrustedStrong.map { map in
                c.pixels.contains(where: { map[$0] })
            } ?? false
            // 원거리 통계가 서로를 억제한 밀집 고대비 먼지는 작은 컴포넌트일 때만 절대 대비 증거로
            // 구제한다. 긴 띠·창문 같은 정상 구조는 이 크기 상한을 넘으므로 strong 우회가 불가능하다.
            let compactTrusted = hasTrustedEvidence && c.pixels.count <= 16
            if !hasStrong, !compactTrusted { continue }
            let trusted = hasStrong ? hasTrustedEvidence : compactTrusted
            // 낮은 임계의 micro-only 경로가 새로 만든 1~2px 컴포넌트는 필름 입자와 구분할 증거가
            // 부족하므로 채택하지 않는다. 기존 보수/큰 이물 strong은 이 제한을 받지 않는다.
            if !trusted, c.pixels.count < microDustMinArea { continue }
            let boxW = c.maxX - c.minX + 1, boxH = c.maxY - c.minY + 1
            let aspect = Double(max(boxW, boxH)) / Double(max(1, min(boxW, boxH)))
            guard passesDustGate(count: c.pixels.count, boxW: boxW, boxH: boxH, aspect: aspect,
                                 maxDustArea: maxDustArea, dustMaxAspect: dustMaxAspect,
                                 minThickDefect: minThickDefect, maxThickDefect: maxThickDefect),
                  isIsolated(c, chunky: chunky, width: width, height: height) else { continue }
            acceptedDust.append(c)
        }
        var acceptedScratch: [RawComponent] = []
        forEachComponent(scratch, width: width, height: height) { comp, minX, maxX, minY, maxY in
            // aspect 스펙트럼은 dust 게이트(≤dustMaxAspect)와 이 스크래치 게이트(≥minScratchAspect)가
            // 함께 커버한다 — 불규칙(중간 aspect) 결함은 dust 로, 가늘고 긴(고 aspect) 결함은 여기로.
            guard let pca = passesScratchGate(comp, width: width, minX: minX, maxX: maxX,
                                              minY: minY, maxY: maxY,
                                              minScratchLength: minScratchLength,
                                              minScratchAspect: minScratchAspect) else { return }
            // 히스테리시스: strong 코어(full-threshold)가 하나라도 있어야 채택 — weak 만으로 된
            // 컴포넌트(그레인/저대비 텍스처)는 버린다. 단 "매우 길고 매우 가는" weak-only 는 기하
            // 증거만으로 채택한다(LSD/a-contrario: SNR floor 통과 픽셀이 이 길이로 정렬-연결될
            // 확률은 지수적으로 작다) — 초저대비 장선 스크래치 검출.
            if let strong = scratchStrong, !comp.contains(where: { strong[$0] }) {
                guard pca.length >= weakGeoMinLength,
                      pca.thickness <= weakGeoMaxThickness,
                      pca.aspect >= weakGeoMinAspect else { return }
            }
            acceptedScratch.append(RawComponent(pixels: comp, minX: minX, maxX: maxX, minY: minY, maxY: maxY))
        }

        // 그레인 필드 필터: 빽빽한 작은 컴포넌트(낱알 그레인)만 버린다(build 와 동일).
        let drops = grainFieldDrops(dust: acceptedDust, scratch: acceptedScratch,
                                    width: width, smallMax: grainFieldSmallMax)
        // 격자/규칙 선 구조 배제(전역 자동 전용). 보도블럭·벽돌·창틀 등 서로 직교하는 두 방향
        // 선이 밀집한 곳의 스크래치 컴포넌트를 버린다 — 고립·평행 다발 스크래치는 보존된다.
        var gridDrops = rejectLineGrid
            ? gridLineDrops(scratch: acceptedScratch, width: width, height: height)
            : []
        // 연장 증거 배제(같은 자동 전용 계약). 개수 기반인 위 판정이 놓치는 **고립 구조선 하나**를
        // 잡는다 — 양 끝 바깥으로 같은 선이 계속되면 원본 이미지의 구조지 필름 결함이 아니다.
        if rejectLineGrid, let scratchResponse {
            gridDrops.formUnion(DefectStructureLineFilter.continuationDrops(
                scratch: acceptedScratch, response: scratchResponse, width: width, height: height))
        }

        for (i, c) in acceptedDust.enumerated() where !drops.dust.contains(i) {
            let id = nextID; nextID += 1
            for p in c.pixels { labels[p] = id }
            components.append(DefectComponent(id: id, kind: .dust, pixels: c.pixels,
                                           minX: c.minX, minY: c.minY, maxX: c.maxX, maxY: c.maxY))
        }
        for (i, c) in acceptedScratch.enumerated() where !drops.scratch.contains(i) && !gridDrops.contains(i) {
            let id = nextID; nextID += 1
            // 먼지와 겹치는 픽셀은 먼지 라벨을 유지(겹침은 드묾). 빈 픽셀만 스크래치로 라벨링.
            for p in c.pixels where labels[p] < 0 { labels[p] = id }
            components.append(DefectComponent(id: id, kind: .scratch, pixels: c.pixels,
                                           minX: c.minX, minY: c.minY, maxX: c.maxX, maxY: c.maxY))
        }
        return DefectLabelField(width: width, height: height, labels: labels, components: components)
    }

    /// 살아남은(excluded 제외) 컴포넌트를 build 와 동일하게 페인팅한 RGBA8 마스크.
    /// dust 는 dustDilate 팽창 + 내부 hole 채움, scratch 는 scratchDilate 만큼 팽창한다.
    /// 자동/브러시 경로는 기존 1px를 유지하고, 사용자가 확인 후 적용하는 영역 결함 제거는 광학적으로
    /// 번진 긴 결함 가장자리까지 포함하도록 더 넓은 값을 전달할 수 있다.
    static func renderMask(_ field: DefectLabelField, excluded: Set<Int32>,
                           maxHoleArea: Int, dustDilate: Int = 0,
                           scratchDilate: Int = 1) -> [UInt8] {
        renderMaskWindow(field, excluded: excluded, maxHoleArea: maxHoleArea,
                         dustDilate: dustDilate, scratchDilate: scratchDilate,
                         windowX: 0, windowY: 0,
                         windowWidth: field.width, windowHeight: field.height)
    }

    /// 필드의 부분 창(field 좌표 y-down, [windowX, windowX+windowWidth) × [windowY, ...))만
    /// 렌더한 마스크. 창이 "생존 컴포넌트 bbox + 팽창 반경"을 전부 덮으면 결과는 전체 렌더를
    /// 같은 창으로 자른 것과 바이트 동일하다 — 큰 검출 ROI 에서 전체 필드 크기 RGBA8 버퍼를
    /// 만들지 않고 결함 창 크기만 할당·페인팅한다(커밋 비용을 결함 크기 비례로).
    static func renderMaskWindow(_ field: DefectLabelField, excluded: Set<Int32>,
                                 maxHoleArea: Int, dustDilate: Int, scratchDilate: Int,
                                 windowX: Int, windowY: Int,
                                 windowWidth: Int, windowHeight: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: max(0, windowWidth * windowHeight * 4))
        guard windowWidth > 0, windowHeight > 0 else { return bytes }
        for comp in field.components where !excluded.contains(comp.id) {
            switch comp.kind {
            case .dust:
                for p in comp.pixels {
                    paintWindow(p, fieldWidth: field.width, radius: dustDilate,
                                windowX: windowX, windowY: windowY,
                                windowWidth: windowWidth, windowHeight: windowHeight, into: &bytes)
                }
                fillInteriorHoles(&bytes,
                                  minX: comp.minX - windowX, maxX: comp.maxX - windowX,
                                  minY: comp.minY - windowY, maxY: comp.maxY - windowY,
                                  width: windowWidth, height: windowHeight,
                                  maxHoleArea: holeCap(maxHoleArea, componentCount: comp.pixels.count))
            case .scratch:
                for p in comp.pixels {
                    paintWindow(p, fieldWidth: field.width, radius: max(1, scratchDilate),
                                windowX: windowX, windowY: windowY,
                                windowWidth: windowWidth, windowHeight: windowHeight, into: &bytes)
                }
            }
        }
        return bytes
    }

    /// paint 의 창 버전 — 필드 픽셀 인덱스를 창 로컬 좌표로 옮겨 사각 페인팅한다.
    private static func paintWindow(_ pixel: Int, fieldWidth: Int, radius r: Int,
                                    windowX: Int, windowY: Int,
                                    windowWidth: Int, windowHeight: Int,
                                    into bytes: inout [UInt8]) {
        let fy = pixel / fieldWidth, fx = pixel - fy * fieldWidth
        let x = fx - windowX, y = fy - windowY
        let y0 = max(0, y - r), y1 = min(windowHeight - 1, y + r)
        let x0 = max(0, x - r), x1 = min(windowWidth - 1, x + r)
        guard y0 <= y1, x0 <= x1 else { return }
        for ny in y0...y1 {
            for nx in x0...x1 {
                let o = (ny * windowWidth + nx) * 4
                bytes[o] = 255; bytes[o + 1] = 255; bytes[o + 2] = 255; bytes[o + 3] = 255
            }
        }
    }
}
