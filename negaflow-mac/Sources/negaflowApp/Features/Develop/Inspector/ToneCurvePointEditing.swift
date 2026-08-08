import Chromabase

enum ToneCurvePointNudge {
    case left
    case right
    case up
    case down
}

enum ToneCurvePointEditing {
    static func ensureSelection(points: inout [CurvePoint], selectedIndex: inout Int?) {
        if points.isEmpty {
            points = [
                CurvePoint(x: 0, y: 0),
                CurvePoint(x: 0.5, y: 0.5),
                CurvePoint(x: 1, y: 1)
            ]
            selectedIndex = 1
        } else if let selectedIndex, points.indices.contains(selectedIndex) {
            return
        } else {
            selectedIndex = 0
        }
    }

    static func nudge(
        points: inout [CurvePoint],
        selectedIndex: inout Int?,
        direction: ToneCurvePointNudge,
        step: Double
    ) {
        ensureSelection(points: &points, selectedIndex: &selectedIndex)
        guard let index = selectedIndex, points.indices.contains(index) else { return }
        var point = points[index]
        switch direction {
        case .left where index > 0 && index < points.count - 1:
            point.x = max(points[index - 1].x + 0.01, point.x - step)
        case .right where index > 0 && index < points.count - 1:
            point.x = min(points[index + 1].x - 0.01, point.x + step)
        case .up:
            point.y = min(1, point.y + step)
        case .down:
            point.y = max(0, point.y - step)
        default:
            return
        }
        points[index] = point
    }

    static func selectAdjacent(points: [CurvePoint], selectedIndex: inout Int?, offset: Int) {
        guard !points.isEmpty else { return }
        let current = selectedIndex.flatMap { points.indices.contains($0) ? $0 : nil } ?? 0
        selectedIndex = min(max(current + offset, 0), points.count - 1)
    }

    static func addPoint(points: inout [CurvePoint], selectedIndex: inout Int?) {
        if points.isEmpty {
            ensureSelection(points: &points, selectedIndex: &selectedIndex)
            return
        }
        let sorted = points.sorted { $0.x < $1.x }
        guard sorted.count >= 2 else { return }
        let gap = (0..<(sorted.count - 1)).max {
            sorted[$0 + 1].x - sorted[$0].x < sorted[$1 + 1].x - sorted[$1].x
        }
        guard let gap else { return }
        let point = CurvePoint(
            x: (sorted[gap].x + sorted[gap + 1].x) / 2,
            y: (sorted[gap].y + sorted[gap + 1].y) / 2
        )
        points = (sorted + [point]).sorted { $0.x < $1.x }
        selectedIndex = points.firstIndex { $0.x == point.x && $0.y == point.y }
    }

    static func deleteSelected(points: inout [CurvePoint], selectedIndex: inout Int?) {
        guard let index = selectedIndex,
              index > 0,
              index < points.count - 1 else { return }
        points.remove(at: index)
        selectedIndex = min(index, points.count - 1)
    }
}
