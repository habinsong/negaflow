import XCTest
@testable import Chromabase

final class IT8ReferenceParserTests: XCTestCase {
    func testParsesCRLFTabLabTableWithImplicitIdentifierColumnAndDensity() throws {
        let fixture = """
        ORIGINATOR\t"OpenDICE Synthetic Fixture"
        MANUFACTURER\t"Synthetic Only"
        SERIAL\tSYN-001
        \tL*\ta*\tb*\tD
        A1\t95.25\t-0.12\t0.41\t
        A16\t63.0\t2.0\t-1.0\t0.350
        L22\t12.5\t1.75\t-2.25\t2.105
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let document = try IT8ReferenceParser.parse(Data(fixture.utf8))

        XCTAssertEqual(document.metadata["ORIGINATOR"], "OpenDICE Synthetic Fixture")
        XCTAssertEqual(document.metadata["MANUFACTURER"], "Synthetic Only")
        XCTAssertEqual(document.metadata["SERIAL"], "SYN-001")
        XCTAssertEqual(document.patches, [
            IT8ReferencePatch(
                id: "A1",
                lab: ColorTargetLab(l: 95.25, a: -0.12, b: 0.41),
                density: nil
            ),
            IT8ReferencePatch(
                id: "A16",
                lab: ColorTargetLab(l: 63.0, a: 2.0, b: -1.0),
                density: 0.350
            ),
            IT8ReferencePatch(
                id: "L22",
                lab: ColorTargetLab(l: 12.5, a: 1.75, b: -2.25),
                density: 2.105
            ),
        ])
    }

    func testParsesTabTableWithExplicitIdentifierAndOptionalDensityOmitted() throws {
        let fixture = """
        ORIGINATOR\t "Synthetic Fixture"\u{20}
        PATCH\tL*\ta*\tb*
        A01\t50\t1.25\t-2.5
        """

        let document = try IT8ReferenceParser.parse(Data(fixture.utf8))
        let patch = try XCTUnwrap(document.patches.first)

        XCTAssertEqual(document.metadata["ORIGINATOR"], "Synthetic Fixture")
        XCTAssertEqual(patch.id, "A01")
        XCTAssertEqual(patch.normalizedID, "A1")
        XCTAssertNil(patch.density)
    }

    func testPatchIDNormalizationIsLimitedToASCIILetterAndDigitGridIDs() {
        XCTAssertEqual(IT8ReferenceParser.normalizedPatchID(" A01 "), "A1")
        XCTAssertEqual(IT8ReferenceParser.normalizedPatchID("a000"), "A0")
        XCTAssertEqual(IT8ReferenceParser.normalizedPatchID("Ä01"), "Ä01")
        XCTAssertEqual(IT8ReferenceParser.normalizedPatchID("A０１"), "A０１")
    }

    func testParsesLegacyCGATSWithQuotedMetadataAndTokens() throws {
        let fixture = """
        IT8.7/1
        ORIGINATOR "Synthetic Reference Generator"
        MANUFACTURER "No Physical Vendor"
        SERIAL "A 01"
        PROD_DATE "2026-07-18"
        MATERIAL "Synthetic transparency"
        DESCRIPTOR "Parser contract fixture"
        NUMBER_OF_FIELDS 5
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B DENSITY
        END_DATA_FORMAT
        NUMBER_OF_SETS 2
        BEGIN_DATA
        "A01" 96.2 -0.1 0.4 0.03
        "B22" 12.5 1.2 -2.3 2.10
        END_DATA
        """

        let document = try IT8ReferenceParser.parse(Data(fixture.utf8))

        XCTAssertEqual(document.metadata["FILE_SIGNATURE"], "IT8.7/1")
        XCTAssertEqual(document.metadata["ORIGINATOR"], "Synthetic Reference Generator")
        XCTAssertEqual(document.metadata["MANUFACTURER"], "No Physical Vendor")
        XCTAssertEqual(document.metadata["SERIAL"], "A 01")
        XCTAssertEqual(document.metadata["PROD_DATE"], "2026-07-18")
        XCTAssertEqual(document.metadata["MATERIAL"], "Synthetic transparency")
        XCTAssertEqual(document.metadata["DESCRIPTOR"], "Parser contract fixture")
        XCTAssertEqual(document.patches.map(\.id), ["A01", "B22"])
        XCTAssertEqual(document.patches.map(\.normalizedID), ["A1", "B22"])
        XCTAssertEqual(document.patches.map(\.density), [0.03, 2.10])
    }

    func testQuotedCGATSTokensSupportHashDoubledQuoteAndEscapedQuote() throws {
        let fixture = """
        ORIGINATOR "Synthetic # Lab"
        DESCRIPTOR "A ""quoted"" target"
        MATERIAL "escaped \\"quote\\""
        NUMBER_OF_FIELDS 4 # structural comment
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0 # data comment
        END_DATA
        """

        let document = try IT8ReferenceParser.parse(Data(fixture.utf8))

        XCTAssertEqual(document.metadata["ORIGINATOR"], "Synthetic # Lab")
        XCTAssertEqual(document.metadata["DESCRIPTOR"], "A \"quoted\" target")
        XCTAssertEqual(document.metadata["MATERIAL"], "escaped \"quote\"")
        XCTAssertEqual(document.patches.count, 1)
    }

    func testEmptyQuotedCGATSDensityIsOptional() throws {
        let fixture = """
        NUMBER_OF_FIELDS 5
        NUMBER_OF_SETS 2
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B DENSITY
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0 ""
        A16 40 0 0 0.75
        END_DATA
        """

        let patches = try IT8ReferenceParser.parse(Data(fixture.utf8)).patches

        XCTAssertNil(patches[0].density)
        XCTAssertEqual(patches[1].density, 0.75)
    }

    func testRejectsNormalizedDuplicateIdentifiersWhilePreservingOriginalIDs() throws {
        let fixture = """
        SAMPLE_ID\tL*\ta*\tb*
        A01\t50\t0\t0
        a1\t51\t0\t0
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(fixture.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .duplicatePatchIdentifier("A1"))
        }
    }

    func testRejectsNonFiniteNumbersAndOutOfRangeLightness() {
        let invalidFixtures: [(String, IT8ReferenceParserError)] = [
            (
                "SAMPLE_ID\tL*\ta*\tb*\nA1\tNaN\t0\t0",
                .invalidNumber(field: "LAB_L", value: "NaN", line: 2)
            ),
            (
                "SAMPLE_ID\tL*\ta*\tb*\nA1\t50\t+Inf\t0",
                .invalidNumber(field: "LAB_A", value: "+Inf", line: 2)
            ),
            (
                "SAMPLE_ID\tL*\ta*\tb*\nA1\t100.01\t0\t0",
                .lightnessOutOfRange(id: "A1", value: 100.01, line: 2)
            ),
            (
                "SAMPLE_ID\tL*\ta*\tb*\tD\nA1\t50\t0\t0\tInf",
                .invalidNumber(field: "DENSITY", value: "Inf", line: 2)
            ),
        ]

        for (fixture, expected) in invalidFixtures {
            XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(fixture.utf8))) { error in
                XCTAssertEqual(error as? IT8ReferenceParserError, expected)
            }
        }
    }

    func testRejectsDeclaredFieldAndSetCountMismatches() {
        let fieldMismatch = """
        NUMBER_OF_FIELDS 5
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        """
        let setMismatch = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 2
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(fieldMismatch.utf8))) { error in
            XCTAssertEqual(
                error as? IT8ReferenceParserError,
                .declaredFieldCountMismatch(expected: 5, actual: 4)
            )
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(setMismatch.utf8))) { error in
            XCTAssertEqual(
                error as? IT8ReferenceParserError,
                .declaredSetCountMismatch(expected: 2, actual: 1)
            )
        }
    }

    func testRejectsRowFieldMismatchAndMissingLabField() {
        let rowMismatch = """
        SAMPLE_ID\tL*\ta*\tb*\tD
        A1\t50\t0\t0
        """
        let missingLab = """
        NUMBER_OF_FIELDS 3
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0
        END_DATA
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(rowMismatch.utf8))) { error in
            XCTAssertEqual(
                error as? IT8ReferenceParserError,
                .fieldCountMismatch(line: 2, expected: 5, actual: 4)
            )
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(missingLab.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .missingField("LAB_B"))
        }
    }

    func testRejectsNestedSectionsDuplicateDensityAliasesAndUnnamedFields() {
        let nestedSection = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        BEGIN_DATA_FORMAT
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        """
        let duplicateDensity = """
        NUMBER_OF_FIELDS 6
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B D DENSITY
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0 0.2 NaN
        END_DATA
        """
        let unnamedField = """
        SAMPLE_ID\tL*\ta*\tb*\t
        A1\t50\t0\t0\tignored
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(nestedSection.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .malformedLine(line: 5))
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(duplicateDensity.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .duplicateField("DENSITY"))
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(unnamedField.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .emptyFieldName(index: 4))
        }
    }

    func testRejectsDuplicateCountDeclarationsAndDataBeforeFormat() {
        let duplicateDeclaration = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        """
        let dataBeforeFormat = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 1
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(duplicateDeclaration.utf8))) {
            error in
            XCTAssertEqual(
                error as? IT8ReferenceParserError,
                .duplicateDeclaration("NUMBER_OF_FIELDS")
            )
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(dataBeforeFormat.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .malformedLine(line: 3))
        }
    }

    func testRejectsStructuralTokensInsideSectionsAndContentAfterData() {
        let declarationInsideData = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        NUMBER_OF_SETS 1
        END_DATA
        """
        let trailingContent = """
        NUMBER_OF_FIELDS 4
        NUMBER_OF_SETS 1
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        B1 60 0 0
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(declarationInsideData.utf8))) {
            error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .malformedLine(line: 7))
        }
        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(trailingContent.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .malformedLine(line: 9))
        }
    }

    func testRejectsUnterminatedQuotedToken() {
        let fixture = """
        ORIGINATOR "unterminated
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS 1
        BEGIN_DATA
        A1 50 0 0
        END_DATA
        """

        XCTAssertThrowsError(try IT8ReferenceParser.parse(Data(fixture.utf8))) { error in
            XCTAssertEqual(error as? IT8ReferenceParserError, .unterminatedQuote(line: 1))
        }
    }
}
