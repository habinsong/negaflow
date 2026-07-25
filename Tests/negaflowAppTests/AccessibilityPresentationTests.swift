import Foundation
import XCTest
@testable import negaflowApp

final class AccessibilityPresentationTests: XCTestCase {
    func testReduceMotionDisablesAnimations() {
        XCTAssertTrue(AppAccessibilityPresentation.disablesAnimations(reduceMotion: true))
        XCTAssertFalse(AppAccessibilityPresentation.disablesAnimations(reduceMotion: false))
    }

    func testReduceTransparencySelectsOpaqueSurfaces() {
        XCTAssertTrue(AppAccessibilityPresentation.usesOpaqueSurfaces(reduceTransparency: true))
        XCTAssertFalse(AppAccessibilityPresentation.usesOpaqueSurfaces(reduceTransparency: false))
    }

    func testIncreasedContrastHasStrongestSurfaceBoundary() {
        let standard = AppAccessibilityPresentation.surfaceStrokeOpacity(
            reduceTransparency: false,
            increasedContrast: false
        )
        let opaque = AppAccessibilityPresentation.surfaceStrokeOpacity(
            reduceTransparency: true,
            increasedContrast: false
        )
        let increased = AppAccessibilityPresentation.surfaceStrokeOpacity(
            reduceTransparency: false,
            increasedContrast: true
        )
        XCTAssertLessThan(standard, opaque)
        XCTAssertLessThan(opaque, increased)
    }

    func testFeatureViewsDoNotBypassAdaptiveMaterialSurfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/negaflowApp", isDirectory: true)
        let allowed = Set(["AdaptiveSurface.swift", "LiquidSurface.swift"])
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return XCTFail("Unable to enumerate \(root.path)")
        }

        let materialTokens = [".regularMaterial", ".ultraThinMaterial", ".thinMaterial"]
        var violations: [String] = []
        for case let file as URL in enumerator
        where file.pathExtension == "swift" && !allowed.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in materialTokens where source.contains(token) {
                violations.append("\(file.path): direct \(token)")
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.sorted().joined(separator: "\n"))
    }
}
