import CoreGraphics
import Foundation

// MARK: - 인화 워터마크(촬영 정보 띠)
//
// 사진 아래(선택하면 위에도) 띠를 덧붙여 카메라·렌즈·노출·촬영 일시·로고·히스토그램·사용자 이름을
// 적는다. 띠는 사진을 자르지 않고 **바깥에 더하는** 영역이다. 배치 수치는 이 파일 한 곳에 두고
// 화면 미리보기와 내보내기가 같은 렌더러(`PrintWatermarkRenderer`)를 거친다.
// Windows `PrintWatermark.cs` 가 같은 수와 규칙을 쓴다.

/// 띠 바탕. 블러는 그 사진을 흐리게 늘려 깐다.
public enum PrintWatermarkBackground: String, CaseIterable, Codable, Sendable {
    case white
    case black
    case blur
}

/// 글자·히스토그램 색. 흰 바탕은 검정, 검정 바탕은 흰색으로 고정이고 블러만 고를 수 있다.
public enum PrintWatermarkInk: String, CaseIterable, Codable, Sendable {
    case black
    case white
}

/// 히스토그램·사용자 이름을 놓는 자리. 위쪽 세 자리는 위 띠가 있을 때만 쓴다.
public enum PrintWatermarkPlacement: String, CaseIterable, Codable, Sendable {
    case bottomCenter
    case topLeading
    case topCenter
    case topTrailing

    public var isTop: Bool { self != .bottomCenter }

    /// 가운데 자리(아래 가운데·위 가운데).
    public var isCenter: Bool { self == .bottomCenter || self == .topCenter }
}

public struct PrintWatermarkSettings: Codable, Equatable, Sendable {
    /// 띠 높이(사진 짧은 변에 대한 비율) 범위.
    public static let bandHeightRange: ClosedRange<Double> = 0.06...0.25
    public static let defaultBandHeightRatio = 0.13
    /// 한 칸에 담는 글자 수 상한. 띠 한 줄을 넘는 글은 레이아웃이 줄여도 읽을 수 없다.
    public static let maximumTextLength = 120
    /// 로고 PNG 상한. 템플릿·설정과 함께 저장되므로 작게 묶는다(로고는 띠 높이의 일부로만 그린다).
    public static let maximumLogoBytes = 2_000_000

    public var isEnabled: Bool
    public var background: PrintWatermarkBackground
    /// 블러 바탕에서 글자(카메라 정보·사용자 이름) 색.
    public var blurTextInk: PrintWatermarkInk
    /// 블러 바탕에서 히스토그램 색.
    public var blurHistogramInk: PrintWatermarkInk
    /// 아래 띠와 같은 높이의 띠를 위에도 더한다.
    public var addsTopBand: Bool
    public var bandHeightRatio: Double
    public var cameraName: String
    public var lensName: String
    public var focalLength: String
    public var aperture: String
    public var shutterSpeed: String
    public var iso: String
    public var captureDate: String
    /// 로고를 넣는다. 켜고 경로를 비워 두면 negaflow 로고를 쓴다.
    public var showsLogo: Bool
    /// 로고 그림(PNG). **저장하지 않는다** — 그릴 때마다 `logoSourcePath`(비었으면 negaflow 로고)에서
    /// 읽어 채운다(앱의 `PrintWatermarkLogoLoader`). 파일이 지워졌거나 열리지 않으면 nil 이고 로고만
    /// 빠진다. 제조사 로고는 앱에 넣지 않는다(상표권) — 사용자가 고른 파일만 쓴다.
    public var logoPNGData: Data?
    /// 로고 파일 경로. 설정과 템플릿에는 이 경로를 저장해 그대로 다시 쓴다.
    public var logoSourcePath: String
    public var showsHistogram: Bool
    public var histogramPlacement: PrintWatermarkPlacement
    public var userName: String
    public var userNamePlacement: PrintWatermarkPlacement

    public init(
        isEnabled: Bool = false,
        background: PrintWatermarkBackground = .white,
        blurTextInk: PrintWatermarkInk = .white,
        blurHistogramInk: PrintWatermarkInk = .white,
        addsTopBand: Bool = false,
        bandHeightRatio: Double = PrintWatermarkSettings.defaultBandHeightRatio,
        cameraName: String = "",
        lensName: String = "",
        focalLength: String = "",
        aperture: String = "",
        shutterSpeed: String = "",
        iso: String = "",
        captureDate: String = "",
        showsLogo: Bool = false,
        logoPNGData: Data? = nil,
        logoSourcePath: String = "",
        showsHistogram: Bool = false,
        histogramPlacement: PrintWatermarkPlacement = .bottomCenter,
        userName: String = "",
        userNamePlacement: PrintWatermarkPlacement = .bottomCenter
    ) {
        self.isEnabled = isEnabled
        self.background = background
        self.blurTextInk = blurTextInk
        self.blurHistogramInk = blurHistogramInk
        self.addsTopBand = addsTopBand
        self.bandHeightRatio = bandHeightRatio
        self.cameraName = cameraName
        self.lensName = lensName
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.captureDate = captureDate
        self.showsLogo = showsLogo
        self.logoPNGData = logoPNGData
        self.logoSourcePath = logoSourcePath
        self.showsHistogram = showsHistogram
        self.histogramPlacement = histogramPlacement
        self.userName = userName
        self.userNamePlacement = userNamePlacement
    }

    public var isValid: Bool {
        bandHeightRatio.isFinite
            && Self.bandHeightRange.contains(bandHeightRatio)
            && texts.allSatisfy { $0.count <= Self.maximumTextLength }
            && (logoPNGData?.count ?? 0) <= Self.maximumLogoBytes
            && logoSourcePath.utf8.count <= Self.maximumPathBytes
    }

    /// 로고 원본 경로 상한(파일 시스템 경로 길이).
    public static let maximumPathBytes = 4_096

    private var texts: [String] {
        [cameraName, lensName, focalLength, aperture, shutterSpeed, iso, captureDate, userName]
    }

    /// 카메라 정보 글자와 사용자 이름의 색.
    public var textInk: PrintWatermarkInk {
        switch background {
        case .white: .black
        case .black: .white
        case .blur: blurTextInk
        }
    }

    public var histogramInk: PrintWatermarkInk {
        switch background {
        case .white: .black
        case .black: .white
        case .blur: blurHistogramInk
        }
    }

    /// 위 띠가 없으면 위쪽 자리는 아래 가운데로 내려온다(값은 남겨 둬 다시 켜면 돌아간다).
    public func effectivePlacement(_ placement: PrintWatermarkPlacement) -> PrintWatermarkPlacement {
        addsTopBand ? placement : .bottomCenter
    }

    /// 노출 한 줄: `100mm f/7.1 1/125 ISO160`. 셔터 속도에는 기호를 붙이지 않는다.
    public var exposureLine: String {
        [
            PrintWatermarkFormat.focalLength(focalLength),
            PrintWatermarkFormat.aperture(aperture),
            PrintWatermarkFormat.shutterSpeed(shutterSpeed),
            PrintWatermarkFormat.iso(iso),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, background, blurTextInk, blurHistogramInk, addsTopBand, bandHeightRatio
        case cameraName, lensName, focalLength, aperture, shutterSpeed, iso, captureDate
        // `logoPNGData` 는 경로에서 다시 읽는 값이라 키에 넣지 않는다(설정·템플릿·내보내기 기록이 그림
        // 바이트를 들고 다니지 않는다).
        case showsLogo, logoSourcePath, showsHistogram, histogramPlacement, userName, userNamePlacement
    }

    /// 항목이 늘어도 예전 설정·템플릿이 읽히도록 빠진 값은 기본값으로 채운다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PrintWatermarkSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        isEnabled = try value(.isEnabled, defaults.isEnabled)
        background = try value(.background, defaults.background)
        blurTextInk = try value(.blurTextInk, defaults.blurTextInk)
        blurHistogramInk = try value(.blurHistogramInk, defaults.blurHistogramInk)
        addsTopBand = try value(.addsTopBand, defaults.addsTopBand)
        bandHeightRatio = try value(.bandHeightRatio, defaults.bandHeightRatio)
        cameraName = try value(.cameraName, defaults.cameraName)
        lensName = try value(.lensName, defaults.lensName)
        focalLength = try value(.focalLength, defaults.focalLength)
        aperture = try value(.aperture, defaults.aperture)
        shutterSpeed = try value(.shutterSpeed, defaults.shutterSpeed)
        iso = try value(.iso, defaults.iso)
        captureDate = try value(.captureDate, defaults.captureDate)
        showsLogo = try value(.showsLogo, defaults.showsLogo)
        logoPNGData = nil
        logoSourcePath = try value(.logoSourcePath, defaults.logoSourcePath)
        showsHistogram = try value(.showsHistogram, defaults.showsHistogram)
        histogramPlacement = try value(.histogramPlacement, defaults.histogramPlacement)
        userName = try value(.userName, defaults.userName)
        userNamePlacement = try value(.userNamePlacement, defaults.userNamePlacement)
    }
}

/// 초점거리·조리개·ISO에 단위를 붙이고 셔터 속도는 입력한 표기를 쓴다.
public enum PrintWatermarkFormat {
    public static func focalLength(_ raw: String) -> String {
        let text = trimmed(raw)
        return isNumber(text) ? "\(text)mm" : text
    }

    public static func aperture(_ raw: String) -> String {
        let text = trimmed(raw)
        return isNumber(text) ? "f/\(text)" : text
    }

    /// 셔터 속도는 앞뒤 공백만 지우고 기호를 덧붙이지 않는다.
    public static func shutterSpeed(_ raw: String) -> String {
        trimmed(raw)
    }

    public static func iso(_ raw: String) -> String {
        let text = trimmed(raw)
        return isNumber(text) ? "ISO\(text)" : text
    }

    /// 소수 끝의 0 을 지운다(`7.10` → `7.1`, `100.0` → `100`).
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 노출 시간(초)을 `1/125` · `2` 꼴로 적는다.
    public static func exposureTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        if seconds >= 1 { return number(seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNumber(_ text: String) -> Bool {
        !text.isEmpty && Double(text) != nil && text.allSatisfy { $0.isNumber || $0 == "." }
    }
}

/// 띠 배치에 쓰는 비율(띠 높이 b 에 대한 배수). 화면과 파일, Mac 과 Windows 가 같은 수를 쓴다.
public enum PrintWatermarkMetrics {
    /// 띠 안 좌우 안쪽 여백.
    public static let horizontalInset: CGFloat = 0.45
    /// 굵은 첫 줄(카메라·노출) 글자 크기.
    public static let primaryFontSize: CGFloat = 0.21
    /// 둘째 줄(렌즈·일시)과 사용자 이름 글자 크기.
    public static let secondaryFontSize: CGFloat = 0.16
    /// 두 줄 사이 간격.
    public static let lineGap: CGFloat = 0.09
    /// 로고 높이(최대 폭은 `logoMaximumWidth`).
    public static let logoHeight: CGFloat = 0.36
    public static let logoMaximumWidth: CGFloat = 2.4
    /// 로고와 노출 글자 사이 세로선.
    public static let separatorHeight: CGFloat = 0.50
    public static let separatorGap: CGFloat = 0.20
    /// 히스토그램 크기와 점 격자(열 × 행).
    public static let histogramWidth: CGFloat = 1.9
    public static let histogramHeight: CGFloat = 0.44
    public static let histogramColumns = 32
    public static let histogramRows = 8
    /// 점 지름 = 칸 간격 × 이 값.
    public static let histogramDotFill: CGFloat = 0.7
    /// 값이 닿지 않은 자리의 옅은 점 불투명도.
    public static let histogramEmptyDotAlpha: CGFloat = 0.18
    /// 한 자리에 히스토그램과 이름이 함께 놓일 때의 간격, 블록 사이 최소 간격.
    public static let itemGap: CGFloat = 0.28
    /// 블러 바탕은 사진을 이 긴 변까지 줄여 흐린다(해상도와 무관하게 같은 모양).
    public static let blurWorkingLongEdge: CGFloat = 256
    public static let blurSigma: CGFloat = 9
}

/// 사진 크기에서 띠와 사진 자리를 정한다. 좌표는 Core Image 와 같은 왼쪽 아래 원점이다.
public struct PrintWatermarkFrameLayout: Equatable, Sendable {
    public let frameSize: CGSize
    public let imageRect: CGRect
    public let bottomBand: CGRect
    public let topBand: CGRect?
    public let bandHeight: CGFloat

    public static func make(
        imageSize: CGSize,
        settings: PrintWatermarkSettings
    ) -> PrintWatermarkFrameLayout? {
        guard settings.isValid,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width >= 1, imageSize.height >= 1 else { return nil }
        let band = max(1, (min(imageSize.width, imageSize.height) * settings.bandHeightRatio).rounded())
        let top = settings.addsTopBand ? band : 0
        let frame = CGSize(width: imageSize.width, height: imageSize.height + band + top)
        return PrintWatermarkFrameLayout(
            frameSize: frame,
            imageRect: CGRect(x: 0, y: band, width: imageSize.width, height: imageSize.height),
            bottomBand: CGRect(x: 0, y: 0, width: imageSize.width, height: band),
            topBand: settings.addsTopBand
                ? CGRect(x: 0, y: band + imageSize.height, width: imageSize.width, height: band)
                : nil,
            bandHeight: band
        )
    }
}
