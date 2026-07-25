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
        to url: URL
    ) throws {
        if frameFormat == .fullFrame35mm {
            try copySimulatorSample(
                baseName: "Roll",
                includesPerforation: includesPerforation,
                to: url
            )
        } else {
            try writeSyntheticFlatbedPreview(
                frameFormat: frameFormat,
                includesPerforation: includesPerforation,
                to: url
            )
        }
    }

    static func writeFlatbedRegion(
        _ area: ScanArea,
        includesPerforation: Bool,
        frameFormat: FilmFrameFormat = .fullFrame35mm,
        to url: URL
    ) throws -> (width: Int, height: Int) {
        guard let sourceImage = try flatbedPreviewImage(
            frameFormat: frameFormat,
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
        includesPerforation: Bool
    ) throws -> CGImage? {
        if frameFormat == .fullFrame35mm {
            let sampleURL = try simulatorSampleURL(
                baseName: "Roll",
                includesPerforation: includesPerforation
            )
            guard let source = CGImageSourceCreateWithURL(sampleURL as CFURL, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return syntheticFlatbedPreviewImage(
            frameFormat: frameFormat,
            includesPerforation: includesPerforation
        )
    }

    private static func writeSyntheticFlatbedPreview(
        frameFormat: FilmFrameFormat,
        includesPerforation: Bool,
        to url: URL
    ) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ScannerError(.ioFailure, "simulator output already exists: \(url.path)")
        }
        guard let image = syntheticFlatbedPreviewImage(
            frameFormat: frameFormat,
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

    private static func syntheticFlatbedPreviewImage(
        frameFormat: FilmFrameFormat,
        includesPerforation: Bool
    ) -> CGImage? {
        let columns: Int
        switch frameFormat {
        case .fullFrame35mm: columns = 6
        case .square35mm: columns = 8
        case .halfFrame35mm: columns = 11
        case .medium645: columns = 4
        case .medium66: columns = 3
        case .medium69: columns = 2
        case .medium612: columns = 1
        }
        let rows = includesPerforation && frameFormat.is35mm ? 3 : 1
        let apertureHeight = 240
        let frameWidth = max(
            64,
            Int((Double(apertureHeight) * frameFormat.stripFrameAspect).rounded())
        )
        let rowPadding = 18
        let rowGap = rows > 1 ? 72 : 0
        let width = frameWidth * columns
        let height = rows * (apertureHeight + rowPadding * 2) + (rows - 1) * rowGap
        var pixels = [UInt8](repeating: 246, count: width * height * 4)

        for row in 0..<rows {
            let apertureTop = row * (apertureHeight + rowPadding * 2 + rowGap) + rowPadding
            for y in apertureTop..<(apertureTop + apertureHeight) {
                for x in 0..<width {
                    let column = x / frameWidth
                    let localX = x % frameWidth
                    let offset = (y * width + x) * 4
                    let boundary = column > 0 && localX < 4
                    let texture = (x * 7 + y * 11 + row * 29 + column * 37) % 92
                    if boundary {
                        pixels[offset] = 242
                        pixels[offset + 1] = 242
                        pixels[offset + 2] = 242
                    } else {
                        pixels[offset] = UInt8(34 + texture)
                        pixels[offset + 1] = UInt8(50 + texture / 2)
                        pixels[offset + 2] = UInt8(72 + texture / 3)
                    }
                    pixels[offset + 3] = 255
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
