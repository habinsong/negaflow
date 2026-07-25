import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Chromabase

// MARK: - 가져온 이미지(RAW/DNG/TIFF/PNG/JPG) 로드→현상 경로 검증
//
// 앱의 "이미지 가져오기"는 sourceKind=.importedFile 프레임을 만들고, 현상/익스포트 파이프라인이
// engine.loadImage(= ImageLoader.load, RAW 데모사이크 + 파일 색공간 보존)로 원본을 읽는다.
// 스캐너 TIFF 전용 loadScannerTIFF와 다른 경로다. 두 경로 모두 ICC를 존중하지만 가져오기는
// EXIF orientation을 적용하고, 스캐너 경로는 장치/세션 transform을 위해 orientation을 무시한다.
// 실제 이미지를 쓰지 않고
// 합성 픽스처로 로드 가능성 + 현상 결과의 유효성을 수치로 확인한다.
final class ImportedImageLoadTests: XCTestCase {
    func testImportedPNGLoadsAndDevelops() throws {
        let url = try writeSyntheticPNG(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ImageLoader.kind(of: url), .standardImage)
        let loaded = try XCTUnwrap(ImageLoader.load(url, allowRaw: true),
                                   "가져온 PNG는 ImageLoader.load 로 로드되어야 한다.")
        XCTAssertEqual(loaded.extent.width, 64, accuracy: 1)
        XCTAssertEqual(loaded.extent.height, 48, accuracy: 1)

        // engine.loadImage 는 앱의 .importedFile 로더 분기가 호출하는 경로다.
        let viaEngine = try XCTUnwrap(ChromabaseEngine().loadImage(url))
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let developed = ChromabaseEngine().developScanner(
            image: viaEngine,
            base: FilmBase(rgb: SIMD3(0.85, 0.55, 0.38), source: .border),
            params: params
        )
        let stats = varianceOfLuma(developed, width: 64, height: 48)
        XCTAssertGreaterThan(stats.range, 0.01,
                             "가져온 이미지를 현상하면 균일 상수가 아닌 계조 있는 결과가 나와야 한다.")
    }

    func testImported16BitTIFFLoads() throws {
        let url = try writeSynthetic16BitTIFF(width: 32, height: 24)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ImageLoader.kind(of: url), .standardImage)
        let loaded = try XCTUnwrap(ImageLoader.load(url, allowRaw: true),
                                   "가져온 16bit TIFF는 ImageLoader.load 로 로드되어야 한다.")
        XCTAssertEqual(loaded.extent.width, 32, accuracy: 1)
        XCTAssertEqual(loaded.extent.height, 24, accuracy: 1)
    }

    // MARK: - 제조사 RAW 확장자 분류
    func testManufacturerRawExtensionsClassifiedAsRaw() {
        let rawByVendor = [
            "crw", "cr2", "cr3",   // Canon
            "nef", "nrw",          // Nikon
            "arw", "srf", "sr2",   // Sony
            "raf",                 // Fujifilm
            "rw2", "raw",          // Panasonic
            "orf",                 // Olympus
            "pef",                 // Pentax
            "srw",                 // Samsung
            "3fr", "fff",          // Hasselblad
            "rwl",                 // Leica
            "iiq",                 // Phase One
            "x3f",                 // Sigma
            "dng",                 // Apple/Google/Adobe/Leica
        ]
        for ext in rawByVendor {
            let url = URL(fileURLWithPath: "/tmp/photo.\(ext)")
            XCTAssertEqual(ImageLoader.kind(of: url), .rawDng, "\(ext) 는 RAW로 분류돼야 한다.")
            XCTAssertTrue(ImageLoader.importExtensions.contains(ext), "\(ext) 는 가져오기 지원에 포함돼야 한다.")
        }
        // 대문자 확장자도 동일하게 분류.
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/tmp/IMG.CR3")), .rawDng)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/tmp/IMG.NEF")), .rawDng)
    }

    func testRawExtensionRejectsStandardImagePayloadWhenRawDecoderFails() throws {
        let pngURL = try writeSyntheticPNG(width: 16, height: 12)
        let rawURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mislabeled_\(UUID().uuidString).cr3")
        try FileManager.default.copyItem(at: pngURL, to: rawURL)
        defer {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: rawURL)
        }

        XCTAssertEqual(ImageLoader.kind(of: rawURL), .rawDng)
        XCTAssertNil(ImageLoader.load(rawURL, allowRaw: true),
                     "RAW 확장자는 CIRAWFilter 디코드 실패 시 PNG/JPEG/TIFF 폴백으로 로드되면 안 된다.")
        XCTAssertNil(ImageLoader.loadImported(rawURL),
                     "가져오기 RAW 경로도 CIRAWFilter가 실패하면 표준 이미지로 위장해 성공하면 안 된다.")
    }

    // MARK: - 색상 프로필 / 스캐너 raw 해석
    //
    // VueScan raw TIFF(16bit, 프로필 없음)는 linear(gamma 1.0). loadImported 는 이를 linear 로 해석해야
    // 한다. 반대로 임베디드 프로필(SilverFast HDRi의 SFprofT 등, 일반 sRGB)은 그 프로필로 색관리해야 한다.
    func testImportedUntagged16BitTIFFDefaultsToStandardImageRole() throws {
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try XCTUnwrap(ImageLoader.loadImportedDecoded(url))

        XCTAssertEqual(decoded.provenance.decoder, .imageIO)
        XCTAssertEqual(decoded.provenance.untaggedTIFFRole, .standardImage)
    }

    func testImportedScannerRawRoleInterpretsUntagged16BitTIFFAsLinear() throws {
        // 프로필 없는 16bit TIFF(값 0.5)를 사용자가 scanner raw로 명시한 경우에만 linear로 해석한다.
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try XCTUnwrap(ImageLoader.loadImportedDecoded(
            url,
            untaggedTIFFRole: .linearScannerRaw
        ))
        let v = renderMidPixelLuma(decoded.image)

        XCTAssertEqual(decoded.provenance.untaggedTIFFRole, .linearScannerRaw)
        XCTAssertEqual(v, 0.5, accuracy: 0.03,
                       "명시한 linear scanner raw는 픽셀 값이 보존돼야 한다. got=\(v)")
    }

    func testEmbeddedSRGBProfileIsHonored() throws {
        // 임베디드 sRGB 프로필(값 0.5) → linear 작업공간 렌더 시 sRGB→linear 변환으로 ~0.214.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: srgb)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try XCTUnwrap(ImageLoader.loadImportedDecoded(url))
        let v = renderMidPixelLuma(decoded.image)
        XCTAssertNil(decoded.provenance.untaggedTIFFRole)
        XCTAssertLessThan(v, 0.35,
                          "임베디드 sRGB 프로필은 존중돼(linear로 강제하지 않아) 0.5가 linear ~0.214로 변환돼야 한다. got=\(v)")
    }

    func testScannerTIFFHonorsEmbeddedSRGBProfile() throws {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: srgb)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(ImageLoader.loadScannerTIFF(url))
        XCTAssertLessThan(renderMidPixelLuma(image), 0.35,
                          "스캐너 TIFF의 임베디드 ICC를 linear raw로 덮어쓰면 안 된다.")
    }

    func testScannerTIFFWithoutProfileRemainsLinear() throws {
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try XCTUnwrap(ImageLoader.loadScannerTIFFDecoded(url))
        XCTAssertEqual(decoded.provenance.untaggedTIFFRole, .linearScannerRaw)
        XCTAssertEqual(renderMidPixelLuma(decoded.image), 0.5, accuracy: 0.03,
                       "무프로필 16bit 스캐너 raw는 linear 값이 보존돼야 한다.")
    }

    func testScannerPreviewUsesSameProfileRuleAsFullResolution() throws {
        let profiled = try writeUniform16BitTIFF(
            value: 0.5,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        let unprofiled = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer {
            try? FileManager.default.removeItem(at: profiled)
            try? FileManager.default.removeItem(at: unprofiled)
        }

        let profiledPreview = try XCTUnwrap(ImageLoader.loadScannerPreview(
            profiled, maxDimension: 4, highResolutionThreshold: 4
        ))
        let unprofiledPreview = try XCTUnwrap(ImageLoader.loadScannerPreview(
            unprofiled, maxDimension: 4, highResolutionThreshold: 4
        ))
        XCTAssertTrue(profiledPreview.usesLinearSRGB,
                      "16bit ICC 입력은 프로파일 변환 후 linear 16bit 프록시로 보존돼야 한다.")
        XCTAssertTrue(unprofiledPreview.usesLinearSRGB)
        XCTAssertLessThan(renderMidPixelLuma(profiledPreview.image), 0.35)
        XCTAssertEqual(renderMidPixelLuma(unprofiledPreview.image), 0.5, accuracy: 0.05)
    }

    func testScannerPreviewIgnoresExifOrientationLikeFullResolutionLoader() throws {
        let url = try writeJPEGWithOrientation(width: 64, height: 32, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let scanner = try XCTUnwrap(ImageLoader.loadScannerPreview(
            url, maxDimension: 16, highResolutionThreshold: 8
        ))
        let imported = try XCTUnwrap(ImageLoader.loadImportedPreview(
            url, maxDimension: 16, highResolutionThreshold: 8
        ))

        XCTAssertGreaterThan(scanner.image.extent.width, scanner.image.extent.height)
        XCTAssertGreaterThan(imported.image.extent.height, imported.image.extent.width)
    }

    // MARK: - EXIF orientation (세로/회전 사진 정립)
    //
    // Core Image는 기본적으로 orientation을 적용하지 않는다. 가져오기 로더는 EXIF orientation을
    // 반영해 세로/회전 카메라 사진이 옆으로 나오지 않게 해야 한다.
    func testExifOrientationAppliedOnImport() throws {
        // 가로(64×32) 이미지를 orientation=6(90° CW)로 저장 → 정립 시 세로(32×64)가 되어야 한다.
        let url = try writeJPEGWithOrientation(width: 64, height: 32, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(ImageLoader.loadImported(url))
        XCTAssertGreaterThan(image.extent.height, image.extent.width,
                             "orientation=6(회전) 사진은 정립되어 세로가 되어야 한다. got \(image.extent.size)")
        XCTAssertEqual(image.extent.width, 32, accuracy: 1)
        XCTAssertEqual(image.extent.height, 64, accuracy: 1)
    }

    func testNoOrientationTagKeepsDimensions() throws {
        // orientation 태그 없음(=1) → 크기 그대로.
        let url = try writeSyntheticPNG(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(ImageLoader.loadImported(url))
        XCTAssertEqual(image.extent.width, 64, accuracy: 1)
        XCTAssertEqual(image.extent.height, 48, accuracy: 1)
    }

    // MARK: - 예외 없는 처리 (다양한 이미지/프로필/손상 파일)
    func testGrayscaleImageLoadsAndDevelops() throws {
        let url = try writeGrayscalePNG(width: 40, height: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try XCTUnwrap(ImageLoader.loadImported(url), "그레이스케일 이미지도 로드돼야 한다.")
        // 흑백 네거티브로 현상 → 크래시 없이 유효 결과.
        var params = DevelopParameters()
        params.filmType = .bwNegative
        let developed = ChromabaseEngine().developScanner(
            image: loaded, base: FilmBase(rgb: SIMD3(0.9, 0.9, 0.9), source: .border), params: params)
        XCTAssertGreaterThan(developed.extent.width, 0)
    }

    func testWideGamutDisplayP3ImageIsHonored() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: p3)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try XCTUnwrap(ImageLoader.loadImported(url), "Display P3 이미지도 로드돼야 한다.")
        // 임베디드 프로필(P3)을 존중 → linear로 강제하지 않는다(0.5 P3 → linear 렌더 시 sRGB감마 해제로 <0.35).
        XCTAssertLessThan(renderMidPixelLuma(loaded), 0.35,
                          "임베디드 P3 프로필을 존중해 감마를 해제해야 한다(linear 강제 아님).")
    }

    func testCorruptFileReturnsNilGracefully() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("corrupt_\(UUID().uuidString).jpg")
        try Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xD8, 0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ImageLoader.loadImported(url), "손상 파일은 크래시 없이 로드 실패(nil)로 끝나야 한다.")
    }

    func testImportExtensionsIncludeStandardAndRaw() {
        for ext in ["jpg", "jpeg", "png", "tiff", "tif", "heic", "cr3", "nef", "arw", "raf", "dng", "rw2"] {
            XCTAssertTrue(ImageLoader.importExtensions.contains(ext), "\(ext) 누락")
        }
    }

    func testDefaultRAWPolicyUsesNoGlobalToneCurve() {
        XCTAssertEqual(ImageLoader.defaultRAWBoostAmount, 0)
    }
}
