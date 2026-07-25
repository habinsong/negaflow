import CoreGraphics
import Foundation

extension InfraredDefectRemoval {
    struct RawComponent {
        var pixels: [Int]
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
    }

    static func labelComponents(
        mask: [Bool], width: Int, height: Int, minArea: Int
    ) -> [RawComponent] {
        let count = width * height
        var visited = [Bool](repeating: false, count: count)
        var components: [RawComponent] = []
        var stack: [Int] = []
        for start in 0..<count where mask[start] && !visited[start] {
            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var component = RawComponent(
                pixels: [], minX: width, minY: height, maxX: 0, maxY: 0
            )
            while let index = stack.popLast() {
                component.pixels.append(index)
                let x = index % width
                let y = index / width
                component.minX = min(component.minX, x)
                component.maxX = max(component.maxX, x)
                component.minY = min(component.minY, y)
                component.maxY = max(component.maxY, y)
                for deltaY in -1...1 {
                    let nextY = y + deltaY
                    guard nextY >= 0, nextY < height else { continue }
                    for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
                        let nextX = x + deltaX
                        guard nextX >= 0, nextX < width else { continue }
                        let next = nextY * width + nextX
                        if mask[next], !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            if component.pixels.count >= minArea { components.append(component) }
        }
        return components
    }

    static func fillHoles(_ component: RawComponent, width: Int, height: Int) -> [Int] {
        let boxWidth = component.maxX - component.minX + 1
        let boxHeight = component.maxY - component.minY + 1
        guard boxWidth >= 3,
              boxHeight >= 3,
              boxWidth * boxHeight <= 512 * 512,
              boxWidth * boxHeight <= component.pixels.count * 64
        else { return component.pixels }

        var local = [Bool](repeating: false, count: boxWidth * boxHeight)
        for pixel in component.pixels {
            let x = pixel % width - component.minX
            let y = pixel / width - component.minY
            local[y * boxWidth + x] = true
        }
        var outside = [Bool](repeating: false, count: boxWidth * boxHeight)
        var stack: [Int] = []
        func push(_ index: Int) {
            if !local[index], !outside[index] {
                outside[index] = true
                stack.append(index)
            }
        }
        for x in 0..<boxWidth { push(x); push((boxHeight - 1) * boxWidth + x) }
        for y in 0..<boxHeight { push(y * boxWidth); push(y * boxWidth + boxWidth - 1) }
        while let index = stack.popLast() {
            let x = index % boxWidth
            let y = index / boxWidth
            if x > 0 { push(index - 1) }
            if x < boxWidth - 1 { push(index + 1) }
            if y > 0 { push(index - boxWidth) }
            if y < boxHeight - 1 { push(index + boxWidth) }
        }
        var result = component.pixels
        for index in 0..<(boxWidth * boxHeight) where !local[index] && !outside[index] {
            let x = index % boxWidth + component.minX
            let y = index / boxWidth + component.minY
            result.append(y * width + x)
        }
        return result
    }

    static func summarize(
        _ component: RawComponent,
        pixels: [Int],
        dev: [Float],
        bCeil: Float,
        width: Int
    ) -> Component {
        var sumX = 0.0, sumY = 0.0, deviationSum = 0.0
        for pixel in component.pixels {
            sumX += Double(pixel % width)
            sumY += Double(pixel / width)
            deviationSum += Double(dev[pixel])
        }
        let count = Double(component.pixels.count)
        let meanX = sumX / count
        let meanY = sumY / count
        var covarianceXX = 0.0, covarianceYY = 0.0, covarianceXY = 0.0
        for pixel in component.pixels {
            let deltaX = Double(pixel % width) - meanX
            let deltaY = Double(pixel / width) - meanY
            covarianceXX += deltaX * deltaX
            covarianceYY += deltaY * deltaY
            covarianceXY += deltaX * deltaY
        }
        covarianceXX /= count
        covarianceYY /= count
        covarianceXY /= count
        let trace = covarianceXX + covarianceYY
        let determinant = covarianceXX * covarianceYY - covarianceXY * covarianceXY
        let discriminant = max(0, trace * trace / 4 - determinant)
        let firstEigenvalue = trace / 2 + discriminant.squareRoot()
        let secondEigenvalue = max(1e-6, trace / 2 - discriminant.squareRoot())
        let elongation = (firstEigenvalue / secondEigenvalue).squareRoot()
        let span = max(component.maxX - component.minX, component.maxY - component.minY) + 1

        var classification: DefectClass = .dust
        if elongation >= 3.5, span >= 16 {
            let angle = abs(
                0.5 * atan2(2 * covarianceXY, covarianceXX - covarianceYY) * 180 / .pi
            )
            if angle <= 30 { classification = .scratchHorizontal }
            else if angle >= 60 { classification = .scratchVertical }
            else { classification = .scratchDiagonal }
        }
        let confidence = min(0.98, max(0.3, deviationSum / count / Double(bCeil)))
        let maximumPointCount = 240
        let stride = max(1, pixels.count / maximumPointCount)
        var points: [CGPoint] = []
        var index = 0
        while index < pixels.count {
            let pixel = pixels[index]
            points.append(CGPoint(x: pixel % width, y: pixel / width))
            index += stride
        }
        return Component(
            classification: classification,
            confidence: confidence,
            area: component.pixels.count,
            previewPoints: points
        )
    }
}
