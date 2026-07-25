import Foundation

enum FilmstripSizing {
    static let defaultHeight = 192.0
    static let legacyDefaultHeight = 168.0
    static let minimumItemScale = 0.56
    static let maximumItemScale = 1.34
    static let nominalItemHeight = 152.0
    static let maximumAutoItemHeight = 156.0
    static let defaultRowFill = 0.92
    static let thumbnailAspectRatio = 3.0 / 2.0

    static func cardWidth(forItemHeight height: Double) -> Double {
        let isCompact = height < 112
        let horizontalPadding = isCompact ? 10.0 : 16.0
        let chromeHeight = isCompact ? 43.0 : 57.0
        let thumbnailHeight = max(24, height - chromeHeight)
        return max(96, thumbnailHeight * thumbnailAspectRatio + horizontalPadding)
    }

    static func clampedHeight(_ height: Double, minimum: Double, maximum: Double) -> Double {
        min(max(height, minimum), maximum)
    }

    static func effectiveItemScale(_ itemScale: Double, filmstripHeight: Double) -> Double {
        let clampedScale = min(max(itemScale, minimumItemScale), maximumItemScale)
        let contentHeight = max(72, filmstripHeight - 7)
        let availableGridHeight = max(72, contentHeight - 20)
        let nominalHeight = nominalItemHeight * clampedScale
        let rowCount = min(3, max(1, Int((availableGridHeight + 10) / (nominalHeight + 10))))
        let fittedRowHeight = max(
            64,
            (availableGridHeight - Double(rowCount - 1) * 10) / Double(rowCount)
        )
        let autoItemHeight = min(
            maximumAutoItemHeight,
            max(58, fittedRowHeight * defaultRowFill)
        )
        let maximumEffectiveScale = min(
            maximumItemScale,
            max(minimumItemScale, fittedRowHeight / autoItemHeight)
        )
        return min(clampedScale, maximumEffectiveScale)
    }

    static func maximumEffectiveItemScale(
        currentItemScale: Double,
        filmstripHeight: Double
    ) -> Double {
        let effective = effectiveItemScale(currentItemScale, filmstripHeight: filmstripHeight)
        return min(
            maximumItemScale,
            max(effective, effectiveItemScale(maximumItemScale, filmstripHeight: filmstripHeight))
        )
    }
}
