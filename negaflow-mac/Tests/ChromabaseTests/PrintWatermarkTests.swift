import CoreGraphics
import CoreImage
import ImageIO
import XCTest
@testable import Chromabase

/// 인화 워터마크(촬영 정보 띠). 합성 화상만 쓰고 결과는 화소 값으로 확인한다.
final class PrintWatermarkTests: XCTestCase {
    private let context = ChromabaseEngine.sharedLinearRenderContext

    func testBandsAreAddedOutsideThePhotoWithoutCropping() throws {
        var settings = PrintWatermarkSettings(isEnabled: true, bandHeightRatio: 0.13)
        let bottomOnly = try XCTUnwrap(PrintWatermarkFrameLayout.make(
            imageSize: CGSize(width: 300, height: 200), settings: settings
        ))
        XCTAssertEqual(bottomOnly.bandHeight, 26)
        XCTAssertEqual(bottomOnly.frameSize, CGSize(width: 300, height: 226))
        XCTAssertEqual(bottomOnly.imageRect, CGRect(x: 0, y: 26, width: 300, height: 200))
        XCTAssertNil(bottomOnly.topBand)

        settings.addsTopBand = true
        let both = try XCTUnwrap(PrintWatermarkFrameLayout.make(
            imageSize: CGSize(width: 200, height: 300), settings: settings
        ))
        // 짧은 변 기준이라 세로 사진도 같은 높이의 띠를 받는다. 위 띠는 아래와 같은 높이다.
        XCTAssertEqual(both.bandHeight, 26)
        XCTAssertEqual(both.frameSize, CGSize(width: 200, height: 352))
        XCTAssertEqual(both.topBand, CGRect(x: 0, y: 326, width: 200, height: 26))
    }

    func testPhotoPixelsSurviveAndBackgroundsFillTheBands() throws {
        let photo = gradientPhoto(width: 240, height: 160)
        let original = try pixels(photo)
        for (background, expected) in [(PrintWatermarkBackground.white, UInt8(255)), (.black, UInt8(0))] {
            let settings = PrintWatermarkSettings(isEnabled: true, background: background, addsTopBand: true)
            let framed = try XCTUnwrap(PrintWatermarkRenderer.compose(
                photo: photo, settings: settings, context: context
            ))
            let band = try XCTUnwrap(PrintWatermarkFrameLayout.make(
                imageSize: photo.extent.size, settings: settings
            )).bandHeight
            XCTAssertEqual(framed.extent.size, CGSize(width: 240, height: 160 + 2 * band))
            let rendered = try pixels(framed)
            // 사진 자리의 화소는 원본과 같다(띠는 바깥에만 더한다).
            for (x, y) in [(5, 5), (120, 80), (230, 150)] {
                XCTAssertEqual(
                    rendered.rgb(x: x, y: y + Int(band)),
                    original.rgb(x: x, y: y),
                    "\(background) 사진 화소 (\(x),\(y))"
                )
            }
            // 글이 없는 띠 가운데는 바탕색 그대로다(위·아래 모두).
            XCTAssertEqual(rendered.rgb(x: 120, y: Int(band) / 2), [expected, expected, expected])
            XCTAssertEqual(
                rendered.rgb(x: 120, y: Int(band) + 160 + Int(band) / 2),
                [expected, expected, expected]
            )
        }
    }

    func testBlurBackgroundTakesTheColorOfThePhoto() throws {
        let red = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 200, height: 150))
        let framed = try XCTUnwrap(PrintWatermarkRenderer.compose(
            photo: red,
            settings: PrintWatermarkSettings(isEnabled: true, background: .blur),
            context: context
        ))
        let pixel = try pixels(framed).rgb(x: 100, y: 3)
        XCTAssertGreaterThan(Int(pixel[0]), 200, "블러 띠는 사진 색(빨강)을 따른다")
        XCTAssertLessThan(Int(pixel[1]), 120)
    }

    func testTextInkFollowsTheBackgroundRule() throws {
        let photo = gradientPhoto(width: 600, height: 400)
        func darkAndBrightCounts(_ settings: PrintWatermarkSettings) throws -> (dark: Int, bright: Int) {
            let framed = try XCTUnwrap(PrintWatermarkRenderer.compose(
                photo: photo, settings: settings, context: context
            ))
            let band = Int(try XCTUnwrap(PrintWatermarkFrameLayout.make(
                imageSize: photo.extent.size, settings: settings
            )).bandHeight)
            let rendered = try pixels(framed)
            var dark = 0
            var bright = 0
            for y in 0..<band {
                for x in 0..<(rendered.width / 3) {
                    let value = rendered.rgb(x: x, y: y)
                    if value.allSatisfy({ $0 < 60 }) { dark += 1 }
                    if value.allSatisfy({ $0 > 200 }) { bright += 1 }
                }
            }
            return (dark, bright)
        }
        var settings = PrintWatermarkSettings(isEnabled: true, cameraName: "MMMM WWWW")
        settings.background = .white
        let onWhite = try darkAndBrightCounts(settings)
        XCTAssertGreaterThan(onWhite.dark, 30, "흰 바탕의 카메라 이름은 검정이다")

        settings.background = .black
        let onBlack = try darkAndBrightCounts(settings)
        XCTAssertGreaterThan(onBlack.bright, 30, "검정 바탕의 카메라 이름은 흰색이다")

        settings.background = .blur
        settings.blurTextInk = .black
        XCTAssertEqual(settings.textInk, .black)
        settings.blurTextInk = .white
        XCTAssertEqual(settings.textInk, .white)
        settings.background = .white
        settings.blurTextInk = .white
        XCTAssertEqual(settings.textInk, .black, "흰 바탕은 고를 수 없고 검정이다")
        XCTAssertEqual(settings.histogramInk, .black)
    }

    func testHistogramMovesToTheTopBandOnlyWhenItExists() throws {
        let photo = gradientPhoto(width: 600, height: 400)
        var settings = PrintWatermarkSettings(
            isEnabled: true,
            background: .white,
            addsTopBand: true,
            showsHistogram: true,
            histogramPlacement: .topLeading
        )
        func inkCount(_ framed: CIImage, rows: Range<Int>) throws -> Int {
            let rendered = try pixels(framed)
            var count = 0
            for y in rows {
                for x in 0..<rendered.width where rendered.rgb(x: x, y: y).allSatisfy({ $0 < 100 }) {
                    count += 1
                }
            }
            return count
        }
        let top = try XCTUnwrap(PrintWatermarkRenderer.compose(photo: photo, settings: settings, context: context))
        let band = 52
        XCTAssertGreaterThan(try inkCount(top, rows: (band + 400)..<(2 * band + 400)), 20)
        XCTAssertEqual(try inkCount(top, rows: 0..<band), 0, "히스토그램이 위로 갔으면 아래 띠는 비어 있다")

        settings.addsTopBand = false
        XCTAssertEqual(settings.effectivePlacement(.topLeading), .bottomCenter)
        let bottom = try XCTUnwrap(PrintWatermarkRenderer.compose(photo: photo, settings: settings, context: context))
        XCTAssertEqual(bottom.extent.height, CGFloat(400 + band))
        XCTAssertGreaterThan(try inkCount(bottom, rows: 0..<band), 20, "위 띠가 없으면 아래 가운데로 내려온다")
    }

    /// 블러 바탕은 필름스트립 썸네일(같은 비율일 때)을 쓴다. 비율이 다르면 오래된 썸네일로 보고 사진을 쓴다.
    func testThumbnailReferenceFeedsTheBlurOnlyWhenItMatchesThePhoto() throws {
        let photo = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.9))
            .cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let settings = PrintWatermarkSettings(isEnabled: true, background: .blur)
        let matching = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 150, height: 100))
        let stale = CIImage(color: CIColor(red: 0.1, green: 0.9, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 150))

        let withThumbnail = try pixels(try XCTUnwrap(PrintWatermarkRenderer.compose(
            photo: photo, settings: settings, reference: matching, context: context
        ))).rgb(x: 300, y: 3)
        XCTAssertGreaterThan(Int(withThumbnail[0]), 200, "같은 비율의 썸네일(빨강)로 흐린다")

        let withStale = try pixels(try XCTUnwrap(PrintWatermarkRenderer.compose(
            photo: photo, settings: settings, reference: stale, context: context
        ))).rgb(x: 300, y: 3)
        XCTAssertGreaterThan(Int(withStale[2]), 200, "비율이 다른 썸네일은 버리고 사진(파랑)으로 흐린다")
    }

    /// 가운데 자리에 히스토그램과 이름이 함께 있으면 가운데 축을 기준으로 데칼코마니처럼 놓인다:
    /// 히스토그램 오른쪽 끝과 이름 왼쪽 끝이 축에서 같은 거리다. 위 띠의 가운데 자리도 같다.
    func testNameStaysCenteredWhenSharingItsSlotWithTheHistogram() throws {
        let photo = gradientPhoto(width: 1_200, height: 800)
        for placement in [PrintWatermarkPlacement.bottomCenter, .topCenter] {
            let settings = PrintWatermarkSettings(
                isEnabled: true,
                background: .white,
                addsTopBand: placement == .topCenter,
                showsHistogram: true,
                histogramPlacement: placement,
                userName: "Mirror",
                userNamePlacement: placement
            )
            let framed = try XCTUnwrap(PrintWatermarkRenderer.compose(photo: photo, settings: settings, context: context))
            let rendered = try pixels(framed)
            let band = 104
            let base = placement == .bottomCenter ? 0 : band + 800
            let rows = base..<(base + 40)
            var inked = [Bool](repeating: false, count: rendered.width)
            for y in rows {
                for x in 0..<rendered.width where rendered.rgb(x: x, y: y).allSatisfy({ $0 < 245 }) {
                    inked[x] = true
                }
            }
            let center = rendered.width / 2
            let left = try XCTUnwrap(inked.firstIndex(of: true))
            let right = try XCTUnwrap(inked.lastIndex(of: true))
            XCTAssertEqual(Double(left + right + 1) / 2, Double(center), accuracy: 4,
                           "\(placement) 이름 자체가 가운데에 있어야 한다")
        }
    }

    /// 세로 사진(띠가 좁다)에 긴 글을 넣어도 글은 줄어들 뿐 띠의 좌우 안쪽 여백을 넘지 않는다.
    /// 예전에는 0.4배 아래로 줄이지 않아 글이 띠(사진) 밖으로 나가 잘렸다.
    func testLongTextShrinksToStayInsideThePortraitBand() throws {
        // 이 글 길이면 전체를 약 0.35배로 줄여야 들어간다(예전 하한 0.4 아래).
        let photo = gradientPhoto(width: 800, height: 1_200)
        let long = String(repeating: "WM", count: 20)
        let settings = PrintWatermarkSettings(
            isEnabled: true,
            background: .white,
            cameraName: long,
            lensName: long,
            focalLength: "100",
            aperture: "7.1",
            shutterSpeed: "1/125",
            iso: "160",
            captureDate: long,
            showsHistogram: true,
            userName: long
        )
        let framed = try XCTUnwrap(PrintWatermarkRenderer.compose(photo: photo, settings: settings, context: context))
        let layout = try XCTUnwrap(PrintWatermarkFrameLayout.make(imageSize: photo.extent.size, settings: settings))
        let rendered = try pixels(framed)
        let band = Int(layout.bandHeight)
        let inset = Int((PrintWatermarkMetrics.horizontalInset * layout.bandHeight).rounded(.down))
        var inkedInside = 0
        for y in 0..<band {
            for x in 0..<rendered.width where rendered.rgb(x: x, y: y).allSatisfy({ $0 < 200 }) {
                XCTAssertTrue(x >= inset - 1 && x <= rendered.width - inset,
                              "띠 안쪽 여백 밖에 글자가 그려졌다 (\(x), \(y))")
                inkedInside += 1
            }
        }
        XCTAssertGreaterThan(inkedInside, 100, "줄어든 글이 실제로 그려져야 한다")
    }

    func testHistogramColumnsCountDisplayBrightness() throws {
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 100, y: 0, width: 300, height: 100))
        let image = white.composited(over: black)
        let columns = try XCTUnwrap(PrintWatermarkHistogram.columns(of: image, count: 32, context: context))
        XCTAssertEqual(columns.count, 32)
        XCTAssertEqual(columns[31], 1, accuracy: 1e-9, "가장 많은 흰색 열이 1 이다")
        XCTAssertEqual(columns[0], 1.0 / 3.0, accuracy: 0.02, "검정은 흰색의 1/3 넓이다")
        XCTAssertEqual(columns[1..<31].reduce(0, +), 0, accuracy: 0.02)
    }

    func testExposureLineAddsUnitsOnlyToBareNumbers() {
        var settings = PrintWatermarkSettings(focalLength: "100", aperture: "7.1", shutterSpeed: "1/125", iso: "160")
        XCTAssertEqual(settings.exposureLine, "100mm f/7.1 1/125 ISO160")
        for speed in ["1/125", "2", "0.5", "B", ""] {
            XCTAssertEqual(PrintWatermarkFormat.shutterSpeed(" \(speed) "), speed)
        }
        settings.focalLength = "28-75mm"
        settings.aperture = "f/2"
        settings.shutterSpeed = "B"
        settings.iso = ""
        XCTAssertEqual(settings.exposureLine, "28-75mm f/2 B")
        XCTAssertEqual(PrintWatermarkFormat.exposureTime(1.0 / 125), "1/125")
        XCTAssertEqual(PrintWatermarkFormat.exposureTime(2), "2")
        XCTAssertEqual(PrintWatermarkFormat.number(7.10), "7.1")
    }

    func testOldSettingsWithoutWatermarkStillDecode() throws {
        let legacy = Data(#"{"paperSize":"a4","orientation":"automatic","marginMM":10,"dpi":300,"perforationStyle":"none"}"#.utf8)
        let decoded = try JSONDecoder().decode(PrintCompositionSettings.self, from: legacy)
        XCTAssertNil(decoded.watermark)
        let partial = try JSONDecoder().decode(
            PrintWatermarkSettings.self,
            from: Data(#"{"isEnabled":true,"cameraName":"X"}"#.utf8)
        )
        XCTAssertTrue(partial.isEnabled)
        XCTAssertEqual(partial.cameraName, "X")
        XCTAssertEqual(partial.bandHeightRatio, PrintWatermarkSettings.defaultBandHeightRatio)
    }

    func testPhotoRatioPaperFollowsEachFramedPhoto() throws {
        let photo = gradientPhoto(width: 1_000, height: 800)
        var settings = PrintCompositionSettings(
            paperSize: .photoRatio,
            marginMM: 0,
            dpi: 72,
            // 다른 사진(3:2)의 비율이 실려 와도 이 장은 자기 비율(띠 포함)을 따른다.
            photoAspectRatio: 1.5
        )
        let plain = try XCTUnwrap(PrintCompositionRenderer.apply(to: photo, settings: settings, context: context))
        XCTAssertEqual(plain.extent.width / plain.extent.height, 1.25, accuracy: 0.01)

        settings.watermark = PrintWatermarkSettings(isEnabled: true, bandHeightRatio: 0.1)
        let framed = try XCTUnwrap(PrintCompositionRenderer.apply(to: photo, settings: settings, context: context))
        XCTAssertEqual(framed.extent.width / framed.extent.height, 1_000.0 / 880.0, accuracy: 0.01)
    }

    func testDisabledWatermarkLeavesTheCompositionUnchanged() throws {
        let photo = gradientPhoto(width: 300, height: 200)
        let base = PrintCompositionSettings(paperSize: .fourBySix, marginMM: 5, dpi: 72)
        var off = base
        off.watermark = PrintWatermarkSettings(isEnabled: false, cameraName: "X")
        let first = try pixels(try XCTUnwrap(PrintCompositionRenderer.apply(to: photo, settings: base, context: context)))
        let second = try pixels(try XCTUnwrap(PrintCompositionRenderer.apply(to: photo, settings: off, context: context)))
        XCTAssertEqual(first.bytes, second.bytes)
    }

    func testLogoIsNormalizedToABoundedPNG() throws {
        let width = 3_000
        let height = 600
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmap = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.setFillColor(CGColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let png = try XCTUnwrap(PrintWatermarkRenderer.normalizedLogoPNG(from: jpeg as Data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(max(image.width, image.height), PrintWatermarkRenderer.maximumLogoPixels)
        XCTAssertNil(PrintWatermarkRenderer.normalizedLogoPNG(from: Data("not an image".utf8)))
    }

    // MARK: - 도우미

    private func gradientPhoto(width: Int, height: Int) -> CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
            "inputColor0": CIColor(red: 0.15, green: 0.35, blue: 0.55),
            "inputColor1": CIColor(red: 0.85, green: 0.65, blue: 0.25),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// 왼쪽 아래 원점 좌표의 RGB.
        func rgb(x: Int, y: Int) -> [UInt8] {
            let row = height - 1 - y
            let index = (row * width + x) * 4
            return Array(bytes[index..<(index + 3)])
        }
    }

    private func pixels(_ image: CIImage) throws -> Pixels {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: image.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return Pixels(width: width, height: height, bytes: bytes)
    }
}
