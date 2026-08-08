import Foundation
import XCTest

final class HardcodedLocalizationTests: XCTestCase {
    func testUserFacingStringsAreNotHardcodedOutsideLocalizationTable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/negaflowApp")
        let files = try swiftSourceFiles(in: sourceRoot)
            .filter { !$0.pathComponents.contains("Localization") }

        var violations: [String] = []
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            let source = try String(contentsOf: file, encoding: .utf8)
            for (lineNumber, line) in source.components(separatedBy: .newlines).enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard line.contains("\""),
                      !trimmedLine.hasPrefix("//"),
                      !trimmedLine.hasPrefix("///"),
                      !isAllowedTechnicalLine(line) else { continue }
                if isUserFacingStringLine(line) || containsHangulString(line) {
                    violations.append("\(relativePath):\(lineNumber + 1): \(trimmedLine)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Localization 폴더 외부에 사용자-facing 하드코딩 문자열이 남아 있습니다.
            \(violations.prefix(120).joined(separator: "\n"))
            """
        )
    }

    private func swiftSourceFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "swift" else { continue }
            let values = try file.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(file)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func isUserFacingStringLine(_ line: String) -> Bool {
        let patterns = [
            "Text(\"",
            "Button(\"",
            "Label(\"",
            "Toggle(\"",
            "Picker(\"",
            "Menu(\"",
            "TextField(\"",
            "InspectorRow(\"",
            "InspectorSlider(\"",
            "InspectorCardHeader(title: \"",
            ".help(\"",
            ".accessibilityLabel(\"",
            ".accessibilityHint(\"",
            ".accessibilityValue(\"",
            "title: \"",
            "subtitle: \"",
            "label: \"",
            "help: \"",
            "statusMessage = \"",
            "processingDetail = \"",
            "diagnosticsStore.append(\"",
            "return \""
        ]
        return patterns.contains { line.contains($0) }
    }

    private func containsHangulString(_ line: String) -> Bool {
        guard line.contains("\"") else { return false }
        return line.range(of: #""[^"]*[가-힣][^"]*""#, options: .regularExpression) != nil
    }

    private func isAllowedTechnicalLine(_ line: String) -> Bool {
        let allowedFragments = [
            "ColorSync",
            "Image(systemName:",
            "Label(model.text(",
            "Text(model.text(",
            "Button(model.text(",
            "Picker(model.text(",
            "Menu(model.text(",
            "Button(\"\")",
            "Toggle(\"\"",
            "Text(\"%\")",
            "TextField(\"100\"",
            "Text(\"\\(resolution.dpi) dpi\")",
            "Text(\"\\(rotation.displayName)°\")",
            "Text(\"JPEG\")",
            "Text(\"PNG\")",
            "Text(\"TIFF 16-bit\")",
            ".statusMessage = \"\"",
            "statusMessage = \"\"",
            "processingDetail = \"\"",
            "circle.lefthalf.filled",
            "moon.fill",
            "sun.max.fill",
            "plusminus.circle",
            "return \"flag\"",
            "return \"flag.fill\"",
            "return \"xmark.octagon.fill\"",
            "return \"rectangle.stack\"",
            "return \"clock.arrow.circlepath\"",
            "return \"slider.horizontal.below.square.and.square.filled\"",
            "return \"camera.filters\"",
            "return \"square.and.arrow.up\"",
            "return \"dc:",
            "return \"xmpRights:",
            "bit/ch",
            "scan-exposure-time",
            "formatNumber(range.minimum))...",
            "ISO",
            "Int(",
            "Toggle(isOn:",
            "ForEach(",
            "UserDefaults",
            "Notification.Name(",
            "DispatchQueue(label:",
            "UTType(",
            "rawValue:",
            "forKey:",
            "suiteName",
            "appendingPathComponent",
            "pathExtension",
            "uniformTypeIdentifier",
            "NSPredicate(format:",
            "#filePath",
            "localized(",
            "String(format:",
            "model.text(",
            "AppLocalization.text(",
            "scanDiagnostics",
            "debugDescription"
        ]
        return allowedFragments.contains { line.contains($0) }
    }
}
