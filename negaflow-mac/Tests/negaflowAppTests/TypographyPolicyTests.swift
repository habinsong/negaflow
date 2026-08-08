import Foundation
import XCTest
@testable import negaflowApp

final class TypographyPolicyTests: XCTestCase {
    func testMinimumReadableTextPolicy() {
        XCTAssertGreaterThanOrEqual(AppTypography.minimumTextPointSize, 10)
        XCTAssertGreaterThanOrEqual(11 * AppTypography.minimumScaleFactor, 10)
    }

    func testAppSourcesDoNotUseAdHocSubminimumPointSizes() throws {
        let violations = try sourceViolations(
            pattern: #"(?:Font\.)?system\(size:\s*([0-9]+(?:\.[0-9]+)?)"#,
            excluding: ["AppTypography.swift"]
        ) { match in
            (Double(match) ?? 10) < 10
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testAppSourcesUseSharedMinimumScaleFactor() throws {
        let violations = try sourceViolations(
            pattern: #"minimumScaleFactor\(\s*([0-9]+(?:\.[0-9]+)?)"#,
            excluding: []
        ) { _ in true }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    private func sourceViolations(
        pattern: String,
        excluding excludedNames: Set<String>,
        isViolation: (String) -> Bool
    ) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/negaflowApp", isDirectory: true)
        let expression = try NSRegularExpression(pattern: pattern)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return ["Unable to enumerate \(root.path)"]
        }

        var violations: [String] = []
        for case let file as URL in enumerator
        where file.pathExtension == "swift" && !excludedNames.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let text = String(line)
                let range = NSRange(text.startIndex..., in: text)
                for match in expression.matches(in: text, range: range) {
                    guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                    let value = String(text[valueRange])
                    if isViolation(value) {
                        violations.append("\(file.path):\(index + 1): \(text)")
                    }
                }
            }
        }
        return violations.sorted()
    }
}
