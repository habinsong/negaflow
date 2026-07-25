import Foundation

extension DefectScratchRepairer {
    static func forEachComponent(_ damaged: [Bool], width: Int, height: Int,
                                 _ body: (_ comp: [Int], _ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> Void) {
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [Int]()
        var comp = [Int]()
        for start in 0..<(width * height) where damaged[start] && !visited[start] {
            stack.removeAll(keepingCapacity: true)
            comp.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            var minX = width
            var maxX = 0
            var minY = height
            var maxY = 0
            while let pixel = stack.popLast() {
                comp.append(pixel)
                let y = pixel / width
                let x = pixel - y * width
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) where nx != x || ny != y {
                        let next = ny * width + nx
                        if damaged[next] && !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            body(comp, minX, maxX, minY, maxY)
        }
    }
}
