import Foundation

// 타일 stitch 이후 **프레임 전체 좌표**에서 구조선 판정을 한 번 더 돌린다(전역 자동 전용, 순수 제거).
//
// 검출은 큰 ROI 를 tileMax 격자로 쪼개 돌리고, 구조선 배제(gridLineDrops)는 각 타일 안에서만
// 판정한다. 그런데 난간·창틀·보도블럭 줄눈처럼 **프레임 전체에 퍼진** 구조는 타일당 선 개수가
// 판정 최소치(gridLineMinField)에 못 미쳐 배제가 아예 켜지지 않는다 — 5088×3401 스캔은 12 타일로
// 쪼개지므로 구조선이 타일마다 몇 개씩만 걸리면 그대로 통과한다. 같은 로직·같은 임계를 전역
// 좌표에서 한 번 더 적용해 그 사각지대만 메운다(임계·검출은 불변, 컴포넌트를 제거만 한다).
extension SoftwareDefectRemoval {
    /// 전역 구조선 판정으로 살아남은 컴포넌트만 남긴 필드. 제거된 컴포넌트의 라벨 픽셀은 배경(-1)이 된다.
    /// - radiusReference: 밀도/구조 반경 기준 변(px). 타일 짧은 변을 넘겨 판정의 물리적 반경을
    ///   타일 검출과 동일하게 유지한다 — 프레임 크기에 비례해 반경이 커지면 큰 스캔에서만 판정이
    ///   공격적으로 변해 진짜 스크래치까지 구조로 몰린다.
    /// - responseMap: 타일 검출이 모아 둔 전역 방향 적분 응답. 연장 증거 판정에 쓴다.
    static func rejectingGlobalStructureLines(_ field: DefectLabelField,
                                              radiusReference: Int,
                                              responseMap: DefectScratchResponseMap?) -> DefectLabelField {
        let scratchIndices = field.components.indices.filter { field.components[$0].kind == .scratch }
        guard scratchIndices.count >= DefectComponentMask.gridLineMinField else { return field }

        let lines = scratchIndices.map { index -> DefectComponentMask.RawComponent in
            let component = field.components[index]
            return DefectComponentMask.RawComponent(
                pixels: component.pixels,
                minX: component.minX, maxX: component.maxX,
                minY: component.minY, maxY: component.maxY
            )
        }
        var drops = DefectComponentMask.gridLineDrops(scratch: lines,
                                                      width: field.width, height: field.height,
                                                      radiusReference: radiusReference)
        // 연장 증거: 컴포넌트 끝 바깥으로 같은 선이 이어지면 원본 이미지의 구조지 필름 결함이 아니다.
        if let responseMap {
            drops.formUnion(DefectStructureLineFilter.continuationDrops(
                scratch: lines, width: field.width,
                responseAt: { x, y in responseMap.value(atX: x, y: y) }))
        }
        guard !drops.isEmpty else { return field }

        var droppedIDs = Set<Int32>()
        for drop in drops { droppedIDs.insert(field.components[scratchIndices[drop]].id) }

        var labels = field.labels
        var survivors: [DefectComponent] = []
        survivors.reserveCapacity(field.components.count - droppedIDs.count)
        for component in field.components {
            guard droppedIDs.contains(component.id) else {
                survivors.append(component)
                continue
            }
            // 라벨은 컴포넌트가 실제로 소유한 픽셀만 되돌린다(먼지와 겹친 픽셀은 먼지 라벨 유지).
            for pixel in component.pixels
            where pixel >= 0 && pixel < labels.count && labels[pixel] == component.id {
                labels[pixel] = -1
            }
        }
        return DefectLabelField(
            width: field.width, height: field.height,
            labels: labels, components: survivors,
            automaticFalsePositiveRisk: field.automaticFalsePositiveRisk,
            automaticCandidatePixelFraction: field.automaticCandidatePixelFraction
        )
    }
}
