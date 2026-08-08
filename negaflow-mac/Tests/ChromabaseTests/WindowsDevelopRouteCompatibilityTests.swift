import Foundation
import XCTest
@testable import Chromabase

final class WindowsDevelopRouteCompatibilityTests: XCTestCase {
    func testWindowsRouteFixtureMatchesDevelopParametersCompatibility() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Negaflow.Windows")
            .appendingPathComponent("tests")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("catalog")
            .appendingPathComponent("develop-route-v1.json")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        let cases = try XCTUnwrap(root["validCases"] as? [[String: Any]])

        for testCase in cases {
            let identifier = try XCTUnwrap(testCase["id"] as? String)
            let frame = try XCTUnwrap(testCase["frame"] as? [String: Any])
            let parametersObject = try XCTUnwrap(frame["params"] as? [String: Any])
            let expected = try XCTUnwrap(testCase["expected"] as? [String: Any])
            let parametersData = try JSONSerialization.data(
                withJSONObject: parametersObject,
                options: [.sortedKeys]
            )
            let parameters = try JSONDecoder().decode(DevelopParameters.self, from: parametersData)

            XCTAssertEqual(
                parameters.filmType.rawValue,
                frame["filmType"] as? String,
                identifier
            )
            XCTAssertEqual(
                parameters.filmEmulation.rawValue,
                expected["filmEmulation"] as? String,
                identifier
            )
            XCTAssertEqual(
                parameters.filmEmulationIntensity,
                try XCTUnwrap(expected["filmEmulationIntensity"] as? Double),
                accuracy: 1e-12,
                identifier
            )

            switch try XCTUnwrap(expected["decodedDigitalMarker"] as? String) {
            case "absent":
                XCTAssertNil(parameters.isDigitalSource, identifier)
            case "true":
                XCTAssertEqual(parameters.isDigitalSource, true, identifier)
            case "false":
                XCTAssertEqual(parameters.isDigitalSource, false, identifier)
            default:
                XCTFail("Unknown decodedDigitalMarker in \(identifier)")
            }
        }
    }

    func testNewDevelopParametersKeepHalfIntensityAndNoDigitalMarker() {
        let parameters = DevelopParameters()
        XCTAssertNil(parameters.isDigitalSource)
        XCTAssertEqual(parameters.filmEmulationIntensity, 0.5, accuracy: 1e-12)
    }
}
