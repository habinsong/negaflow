import CoreGraphics
import Foundation
import XCTest
@testable import Chromabase

/// [작업 4] 인화 판 기하 — 캔버스 화소 크기 / 이미지 사각형 / 천공 개수.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task4-print \
/// swift test --filter MacGoldenPrintGeometryHarnessTests
/// ```
///
/// 단판(single sheet)은 `PrintCompositionLayout` 이 화소로 직접 계산하고, 컨택트 시트는
/// `PrintPackageLayout` 이 **포인트**로 계산한 뒤 렌더러가 `dpi/72` 로 화소를 만든다.
/// 그래서 시트 쪽은 포인트 값과 렌더 화소 값을 둘 다 적는다.
///
/// 이미지 사각형은 원본 사진의 종횡비에 직접 의존하므로, 실제 스캔 크기와 규격 2:3 세로를
/// 모두 돌린다. Windows 와 비교할 때는 **같은 원본 크기**끼리 맞춰 봐야 한다.
final class MacGoldenPrintGeometryHarnessTests: XCTestCase {

    /// 실제 golden 스캔(GT-X900_frame_4.tiff)의 화소 크기 — 세로 사진.
    private static let scanPortrait = CGSize(width: 2_272, height: 3_471)
    /// 종횡비 의존을 제거하고 비교하기 위한 규격 2:3 세로.
    private static let canonicalPortrait = CGSize(width: 2_400, height: 3_600)

    func testEmitsPrintGeometryGolden() throws {
        guard let outputDirectory = MacGoldenHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }

        var singleSheets: [[String: Any]] = []
        for (label, size) in [
            ("scan-2272x3471", Self.scanPortrait),
            ("canonical-2400x3600", Self.canonicalPortrait),
        ] {
            for style in [PrintPerforationStyle.none, .thirtyFiveMillimeter] {
                let settings = PrintCompositionSettings(
                    paperSize: .a4,
                    orientation: .portrait,
                    marginMM: 10,
                    dpi: 300,
                    perforationStyle: style
                )
                let layout = try XCTUnwrap(
                    PrintCompositionLayout.make(sourceSize: size, settings: settings),
                    "\(label)/\(style.rawValue) 레이아웃 실패"
                )
                singleSheets.append([
                    "case": "a4-300dpi-portrait-\(style.rawValue)",
                    "sourceLabel": label,
                    "sourceSize": Self.encode(size),
                    "settings": [
                        "paperSize": settings.paperSize.rawValue,
                        "orientation": settings.orientation.rawValue,
                        "marginMM": settings.marginMM,
                        "dpi": settings.dpi,
                        "perforationStyle": style.rawValue,
                    ],
                    "canvasSizePx": Self.encode(layout.canvasSize),
                    "contentRectPx": Self.encode(layout.contentRect),
                    "imageRectPx": Self.encode(layout.imageRect),
                    "imageSizeRoundedPx": [
                        "width": Int(layout.imageRect.width.rounded()),
                        "height": Int(layout.imageRect.height.rounded()),
                    ],
                    "filmRectPx": layout.filmRect.map(Self.encode) ?? NSNull(),
                    "perforationCount": layout.perforationRects.count,
                    "perforationCornerRadiusPx": layout.perforationCornerRadius,
                    "firstPerforationRectPx": layout.perforationRects.first.map(Self.encode)
                        ?? NSNull(),
                ])
            }
        }

        // 컨택트 시트 4열 × 3행, 사진 12장.
        let composition = PrintCompositionSettings(
            paperSize: .a4,
            orientation: .automatic,
            marginMM: 10,
            dpi: 300,
            perforationStyle: .none
        )
        var package = PrintPackageSettings()
        package.mode = .contactSheet
        package.contactColumns = 4
        package.contactRows = 3
        let sources = Array(repeating: Self.scanPortrait, count: 12)
        let pages = try XCTUnwrap(
            PrintPackageLayout.make(
                sourceSizes: sources,
                composition: composition,
                package: package
            ),
            "컨택트 시트 레이아웃 실패"
        )
        let pixelsPerPoint = CGFloat(composition.dpi) / 72
        let contact: [[String: Any]] = pages.map { page in
            [
                "pageIndex": page.pageIndex,
                "canvasSizePoints": Self.encode(page.canvasSizePoints),
                "canvasSizePx": [
                    "width": Int(max(1, (page.canvasSizePoints.width * pixelsPerPoint).rounded())),
                    "height": Int(max(1, (page.canvasSizePoints.height * pixelsPerPoint).rounded())),
                ],
                "contentRectPoints": Self.encode(page.contentRectPoints),
                "cellCount": page.items.count,
                "items": page.items.map { item in
                    [
                        "sourceIndex": item.sourceIndex,
                        "cellRectPoints": Self.encode(item.cellRectPoints),
                        "destinationRectPoints": Self.encode(item.destinationRectPoints),
                        "destinationSizePx": [
                            "width": item.destinationRectPoints.width * pixelsPerPoint,
                            "height": item.destinationRectPoints.height * pixelsPerPoint,
                        ],
                        "quarterTurns": item.quarterTurns,
                    ] as [String: Any]
                },
            ]
        }

        let manifest: [String: Any] = [
            "task": "4 · print sheet geometry",
            "singleSheets": singleSheets,
            "contactSheet": [
                "settings": [
                    "paperSize": composition.paperSize.rawValue,
                    "orientation": composition.orientation.rawValue,
                    "marginMM": composition.marginMM,
                    "dpi": composition.dpi,
                    "columns": package.contactColumns,
                    "rows": package.contactRows,
                    "sourceCount": sources.count,
                    "horizontalSpacingMM": package.horizontalSpacingMM,
                    "verticalSpacingMM": package.verticalSpacingMM,
                    "contentMode": package.contentMode.rawValue,
                    "captionMode": package.captionMode.rawValue,
                    "showsCropMarks": package.showsCropMarks,
                ],
                "expectedPageCount": PrintPackageLayout.expectedPageCount(
                    sourceCount: sources.count,
                    package: package
                ) ?? -1,
                "pages": contact,
            ],
        ]
        try MacGoldenHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("print-geometry.json")
        )
    }

    private static func encode(_ size: CGSize) -> [String: Any] {
        ["width": size.width, "height": size.height]
    }

    private static func encode(_ rect: CGRect) -> [String: Any] {
        [
            "x": rect.origin.x, "y": rect.origin.y,
            "width": rect.width, "height": rect.height,
        ]
    }
}
