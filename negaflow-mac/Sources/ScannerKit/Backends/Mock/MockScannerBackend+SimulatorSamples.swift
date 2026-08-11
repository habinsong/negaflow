import CoreGraphics
import Chromabase
import Foundation
import ImageIO

extension MockScannerBackend {
    static func simulatorSampleURL(
        baseName: String,
        includesPerforation: Bool
    ) throws -> URL {
        let resourceName = includesPerforation ? "\(baseName)_Perforation" : baseName
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "tiff") else {
            throw ScannerError(.ioFailure, "missing simulator sample: \(resourceName).tiff")
        }
        return url
    }

    static func writeSimulatorFrame(
        includesPerforation: Bool,
        to url: URL
    ) throws {
        try copySimulatorSample(
            baseName: "Frame",
            includesPerforation: includesPerforation,
            to: url
        )
    }

    static func writeFlatbedPreview(
        includesPerforation: Bool,
        frameFormat: FilmFrameFormat = .fullFrame35mm,
        frameOrientation: FilmFrameOrientation = .landscape,
        frameCount: Int = 6,
        frameOrientations: [FilmFrameOrientation]? = nil,
        missingFrameIndices: Set<Int> = [],
        to url: URL
    ) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ScannerError(.ioFailure, "simulator output already exists: \(url.path)")
        }
        guard let image = try flatbedPreviewImage(
            frameFormat: frameFormat,
            frameOrientation: frameOrientation,
            frameCount: frameCount,
            frameOrientations: frameOrientations,
            missingFrameIndices: missingFrameIndices,
            includesPerforation: includesPerforation
        ), let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.tiff" as CFString,
            1,
            nil
        ) else {
            throw ScannerError(.ioFailure, "simulator format preview image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "simulator format preview write")
        }
    }

    static func writeFlatbedRegion(
        _ area: ScanArea,
        includesPerforation: Bool,
        frameFormat: FilmFrameFormat = .fullFrame35mm,
        frameOrientation: FilmFrameOrientation = .landscape,
        frameCount: Int = 6,
        frameOrientations: [FilmFrameOrientation]? = nil,
        missingFrameIndices: Set<Int> = [],
        to url: URL
    ) throws -> (width: Int, height: Int) {
        guard let sourceImage = try flatbedPreviewImage(
            frameFormat: frameFormat,
            frameOrientation: frameOrientation,
            frameCount: frameCount,
            frameOrientations: frameOrientations,
            missingFrameIndices: missingFrameIndices,
            includesPerforation: includesPerforation
        ),
              let cropRect = flatbedPreviewCropRect(
                  for: area,
                  imageSize: CGSize(width: sourceImage.width, height: sourceImage.height)
              ),
              let cropped = sourceImage.cropping(to: cropRect) else {
            throw ScannerError(.ioFailure, "simulator flatbed region crop")
        }
        let size = flatbedRegionPixelSize(for: cropRect.size)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size.width,
                  height: size.height,
                  bitsPerComponent: 8,
                  bytesPerRow: size.width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScannerError(.ioFailure, "simulator flatbed region context")
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  "public.tiff" as CFString,
                  1,
                  nil
              ) else {
            throw ScannerError(.ioFailure, "simulator flatbed region image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "simulator flatbed region write")
        }
        return size
    }

    private static func flatbedPreviewImage(
        frameFormat: FilmFrameFormat,
        frameOrientation: FilmFrameOrientation,
        frameCount: Int,
        frameOrientations: [FilmFrameOrientation]?,
        missingFrameIndices: Set<Int>,
        includesPerforation: Bool
    ) throws -> CGImage? {
        let content = syntheticFlatbedPreviewImage(
            frameFormat: frameFormat,
            frameOrientation: frameOrientation,
            frameCount: frameCount,
            frameOrientations: frameOrientations,
            missingFrameIndices: missingFrameIndices,
            includesPerforation: includesPerforation
        )
        guard let content else { return nil }
        return embeddedInFlatbedCanvas(content)
    }

    private static func embeddedInFlatbedCanvas(_ content: CGImage) -> CGImage? {
        // Mock capability의 210 × 297 mm 작업면과 같은 비율을 유지해야 정규화 ROI가
        // 실제 장치와 동일한 물리 좌표로 환산된다.
        let canvasWidth = 1_400
        let canvasHeight = 1_980
        let margin = 80.0
        let availableWidth = Double(canvasWidth) - margin * 2
        let availableHeight = Double(canvasHeight) - margin * 2
        let scale = min(
            availableWidth / Double(content.width),
            availableHeight / Double(content.height)
        )
        guard scale.isFinite, scale > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: canvasWidth,
                  height: canvasHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: canvasWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high
        let width = Double(content.width) * scale
        let height = Double(content.height) * scale
        // 필름을 판 한가운데에 정확히 두지 않는다. 정중앙이면 y 를 뒤집어도 같은 자리에
        // 떨어져, 좌표계를 잘못 매핑해도 결과가 맞는 것처럼 보인다. 실제로도 홀더는 판
        // 위쪽에 치우쳐 놓인다.
        let verticalOffset = Double(canvasHeight) * 0.06
        context.draw(
            content,
            in: CGRect(
                x: (Double(canvasWidth) - width) / 2,
                y: (Double(canvasHeight) - height) / 2 + verticalOffset,
                width: width,
                height: height
            )
        )
        return context.makeImage()
    }

    private static func syntheticFlatbedPreviewImage(
        frameFormat: FilmFrameFormat,
        frameOrientation: FilmFrameOrientation,
        frameCount: Int,
        frameOrientations: [FilmFrameOrientation]?,
        missingFrameIndices: Set<Int>,
        includesPerforation: Bool
    ) -> CGImage? {
        guard (1...48).contains(frameCount) else { return nil }
        let orientations = frameOrientations?.count == frameCount
            ? frameOrientations!
            : Array(repeating: frameOrientation, count: frameCount)
        let rows = includesPerforation && frameFormat.is35mm ? 3 : 1
        let apertureHeight = 240
        let frameWidths = orientations.map {
            max(64, Int((Double(apertureHeight) * $0.aspect(for: frameFormat)).rounded()))
        }
        let rowPadding = 18
        // 스트립 사이 마스크는 컷 하나보다 넓다. 좁게 그리면 검출기가 위아래 스트립을 한
        // 줄로 이어 붙여(끊긴 필름을 잇는 규칙에 걸린다) 컷을 통째로 잃는다.
        let rowGap = rows > 1 ? apertureHeight * 3 / 2 : 0
        // 컷 사이는 홀더가 막는다. 실제 홀더는 창과 창 사이가 불투명한 마스크이고, 검출기는
        // 그 경계로 슬롯을 가른다. 여기를 몇 픽셀만 띄우면 시뮬레이터가 실제 장치와 다른
        // 그림(칸이 붙어 있는 콘택트 시트)을 보여 준다.
        let slotGutter = 24
        let contentWidth = frameWidths.reduce(0, +) + slotGutter * max(0, frameCount - 1)
        let width = max(256, contentWidth + 48)
        let height = rows * (apertureHeight + rowPadding * 2) + (rows - 1) * rowGap
        var pixels = [UInt8](repeating: 246, count: width * height * 4)
        for offset in stride(from: 3, to: pixels.count, by: 4) {
            pixels[offset] = 255
        }
        var slotRanges: [Range<Int>] = []
        slotRanges.reserveCapacity(frameCount)
        var slotStart = (width - contentWidth) / 2
        for frameWidth in frameWidths {
            slotRanges.append(slotStart..<(slotStart + frameWidth))
            slotStart += frameWidth + slotGutter
        }

        for row in 0..<rows {
            let apertureTop = row * (apertureHeight + rowPadding * 2 + rowGap) + rowPadding
            for y in apertureTop..<(apertureTop + apertureHeight) {
                for (column, range) in slotRanges.enumerated()
                    where !missingFrameIndices.contains(column) {
                    for x in range {
                        let localX = x - range.lowerBound
                        let offset = (y * width + x) * 4
                        let boundary = localX < 8 || range.upperBound - x <= 8
                        let texture = (x * 7 + y * 11 + row * 29 + column * 37) % 92
                        if boundary {
                            pixels[offset] = 246
                            pixels[offset + 1] = 246
                            pixels[offset + 2] = 246
                        } else {
                            let horizontalTone = localX * 60 / max(range.count - 1, 1)
                            // 컷 안에서 위아래가 달라야 한다. 캔버스 전체 y 로 기울이면 컷
                            // 하나만 떼어 봤을 때 위아래가 거의 같아서, 뒤집힌 매핑도 맞는
                            // 것처럼 보인다.
                            let verticalTone = (y - apertureTop) * 70 / max(apertureHeight - 1, 1)
                            pixels[offset] = UInt8(
                                min(235, 24 + texture / 4 + horizontalTone + column * 12)
                            )
                            pixels[offset + 1] = UInt8(
                                min(235, 36 + texture / 5 + verticalTone + row * 18)
                            )
                            pixels[offset + 2] = UInt8(
                                min(
                                    235,
                                    52 + texture / 6 + (horizontalTone + verticalTone) / 2
                                        + column * 7 + row * 9
                                )
                            )
                        }
                        pixels[offset + 3] = 255
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func flatbedPreviewCropRect(
        for area: ScanArea,
        imageSize: CGSize
    ) -> CGRect? {
        let bedWidthMM = 210.0
        let bedHeightMM = 297.0
        guard area.originXMM.isFinite, area.originYMM.isFinite,
              area.widthMM.isFinite, area.heightMM.isFinite,
              area.widthMM > 0, area.heightMM > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let unitBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let unitRect = CGRect(
            x: area.originXMM / bedWidthMM,
            y: area.originYMM / bedHeightMM,
            width: area.widthMM / bedWidthMM,
            height: area.heightMM / bedHeightMM
        ).intersection(unitBounds)
        guard !unitRect.isNull, unitRect.width > 0, unitRect.height > 0 else { return nil }
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let pixelRect = CGRect(
            x: unitRect.minX * imageSize.width,
            // ScanArea/SANE의 Y 원점은 센서가 보는 평판의 좌상단이고, CGImage crop 좌표는
            // 좌하단이다. 프리뷰에서 고른 동일한 위치를 자르도록 좌표계를 변환한다.
            y: (1 - unitRect.maxY) * imageSize.height,
            width: unitRect.width * imageSize.width,
            height: unitRect.height * imageSize.height
        ).integral.intersection(imageBounds)
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return pixelRect
    }

    static func flatbedRegionPixelSize(for cropSize: CGSize) -> (width: Int, height: Int) {
        let ratio = cropSize.width / cropSize.height
        guard ratio.isFinite, ratio > 0 else { return (1_600, 1_067) }
        let longestSide = 1_600.0
        if ratio >= 1 {
            return (Int(longestSide), max(1, Int((longestSide / ratio).rounded())))
        }
        return (max(1, Int((longestSide * ratio).rounded())), Int(longestSide))
    }

    private static func copySimulatorSample(
        baseName: String,
        includesPerforation: Bool,
        to destination: URL
    ) throws {
        let source = try simulatorSampleURL(
            baseName: baseName,
            includesPerforation: includesPerforation
        )
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ScannerError(.ioFailure, "simulator output already exists: \(destination.path)")
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ScannerError(.ioFailure, "simulator sample copy failed: \(error.localizedDescription)")
        }
    }
}
