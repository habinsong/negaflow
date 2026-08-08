import Foundation

/// Patch-level output of the deterministic NORITSU/FUJI relative-style regression.
///
/// This report deliberately does not describe device accuracy. Its scanner transforms come
/// from the bundled roll-label aggregate profiles, while the target itself is a synthetic
/// color-negative forward model.
public struct ScannerRelativeIT8BenchmarkReport: Codable, Equatable, Sendable {
    public enum EvidenceClass: String, Codable, Sendable {
        case syntheticModel
    }

    public enum QualityDecision: String, Codable, Sendable {
        case notEvaluated
    }

    public struct RGB: Codable, Equatable, Sendable {
        public let r: Double
        public let g: Double
        public let b: Double

        public init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public enum WorkingRangeFlag: String, Codable, Sendable {
        case containsChannelAtZeroEndpoint
        case containsChannelAtOneEndpoint
        case containsChannelBelowZero
        case containsChannelAboveOne
        case containsNonFiniteChannel
    }

    public struct ReferenceIdentity: Codable, Equatable, Sendable {
        public enum ColorimetryInterpretationProvenance: String, Codable, Sendable {
            case benchmarkContractNotVerifiedFromReferenceHeader
        }

        public let sha256: String
        public let patchCount: Int
        public let interpretedIlluminant: String
        public let interpretedObserver: String
        public let colorimetryInterpretationProvenance: ColorimetryInterpretationProvenance

        public init(
            sha256: String,
            patchCount: Int,
            interpretedIlluminant: String,
            interpretedObserver: String,
            colorimetryInterpretationProvenance: ColorimetryInterpretationProvenance =
                .benchmarkContractNotVerifiedFromReferenceHeader
        ) {
            self.sha256 = sha256
            self.patchCount = patchCount
            self.interpretedIlluminant = interpretedIlluminant
            self.interpretedObserver = interpretedObserver
            self.colorimetryInterpretationProvenance = colorimetryInterpretationProvenance
        }
    }

    public struct SyntheticModel: Codable, Equatable, Sendable {
        public let modelName: String
        public let filmBaseLinearRGB: RGB
        public let densityEncodingVersion: String
        public let densityEncodingRange: Double
        public let rows: Int
        public let columns: Int
        public let patchSize: Int

        public init(
            modelName: String,
            filmBaseLinearRGB: RGB,
            densityEncodingVersion: String,
            densityEncodingRange: Double,
            rows: Int,
            columns: Int,
            patchSize: Int
        ) {
            self.modelName = modelName
            self.filmBaseLinearRGB = filmBaseLinearRGB
            self.densityEncodingVersion = densityEncodingVersion
            self.densityEncodingRange = densityEncodingRange
            self.rows = rows
            self.columns = columns
            self.patchSize = patchSize
        }
    }

    public struct RelativeProfilePairIdentity: Codable, Equatable, Sendable {
        public let kind: String
        public let filmKey: String
        public let noritsuProfileID: String
        public let fujiProfileID: String
        public let noritsuImageCount: Int
        public let fujiImageCount: Int
        public let pairingEvidence: String
        public let exactFramePairingProven: Bool

        public init(
            kind: String,
            filmKey: String,
            noritsuProfileID: String,
            fujiProfileID: String,
            noritsuImageCount: Int,
            fujiImageCount: Int,
            pairingEvidence: String = "normalized-roll-label-set-and-image-count-tolerance",
            exactFramePairingProven: Bool = false
        ) {
            self.kind = kind
            self.filmKey = filmKey
            self.noritsuProfileID = noritsuProfileID
            self.fujiProfileID = fujiProfileID
            self.noritsuImageCount = noritsuImageCount
            self.fujiImageCount = fujiImageCount
            self.pairingEvidence = pairingEvidence
            self.exactFramePairingProven = exactFramePairingProven
        }
    }

    public struct RenderMeasurement: Codable, Equatable, Sendable {
        /// Nil only when one or more rendered channels are non-finite.
        public let linearRGB: RGB?
        /// Nil only when `linearRGB` cannot be converted to a finite Lab value.
        public let labD50: ColorTargetLab?
        public let deltaE00FromReference: Double?
        public let workingRangeFlags: [WorkingRangeFlag]

        public init(
            linearRGB: RGB?,
            labD50: ColorTargetLab?,
            deltaE00FromReference: Double?,
            workingRangeFlags: [WorkingRangeFlag]
        ) {
            self.linearRGB = linearRGB
            self.labD50 = labD50
            self.deltaE00FromReference = deltaE00FromReference
            self.workingRangeFlags = workingRangeFlags
        }
    }

    public struct Patch: Codable, Equatable, Sendable {
        public let id: String
        public let row: Int
        public let column: Int
        public let referenceLabD50: ColorTargetLab
        public let inputLinearRGB: RGB
        public let inputLabD50: ColorTargetLab
        public let inputDeltaE00FromReference: Double
        public let syntheticNegativeTransmissionRGB: RGB
        public let inputWorkingRangeFlags: [WorkingRangeFlag]
        public let main: RenderMeasurement
        public let noritsu: RenderMeasurement
        public let fuji: RenderMeasurement
        public let noritsuDeltaE00FromMain: Double?
        public let fujiDeltaE00FromMain: Double?
        public let noritsuFujiDeltaE00: Double?
        public let valid: Bool

        public init(
            id: String,
            row: Int,
            column: Int,
            referenceLabD50: ColorTargetLab,
            inputLinearRGB: RGB,
            inputLabD50: ColorTargetLab,
            inputDeltaE00FromReference: Double,
            syntheticNegativeTransmissionRGB: RGB,
            inputWorkingRangeFlags: [WorkingRangeFlag],
            main: RenderMeasurement,
            noritsu: RenderMeasurement,
            fuji: RenderMeasurement,
            noritsuDeltaE00FromMain: Double?,
            fujiDeltaE00FromMain: Double?,
            noritsuFujiDeltaE00: Double?,
            valid: Bool
        ) {
            self.id = id
            self.row = row
            self.column = column
            self.referenceLabD50 = referenceLabD50
            self.inputLinearRGB = inputLinearRGB
            self.inputLabD50 = inputLabD50
            self.inputDeltaE00FromReference = inputDeltaE00FromReference
            self.syntheticNegativeTransmissionRGB = syntheticNegativeTransmissionRGB
            self.inputWorkingRangeFlags = inputWorkingRangeFlags
            self.main = main
            self.noritsu = noritsu
            self.fuji = fuji
            self.noritsuDeltaE00FromMain = noritsuDeltaE00FromMain
            self.fujiDeltaE00FromMain = fujiDeltaE00FromMain
            self.noritsuFujiDeltaE00 = noritsuFujiDeltaE00
            self.valid = valid
        }
    }

    public struct RepeatabilitySummary: Codable, Equatable, Sendable {
        public let mainBitExact: Bool
        public let noritsuBitExact: Bool
        public let fujiBitExact: Bool
        public let allTargetsBitExact: Bool

        public init(mainBitExact: Bool, noritsuBitExact: Bool, fujiBitExact: Bool) {
            self.mainBitExact = mainBitExact
            self.noritsuBitExact = noritsuBitExact
            self.fujiBitExact = fujiBitExact
            allTargetsBitExact = mainBitExact && noritsuBitExact && fujiBitExact
        }
    }

    public struct NeutralToneTargetSummary: Codable, Equatable, Sendable {
        public let expectedAdjacentPairCount: Int
        public let comparedAdjacentPairCount: Int
        public let reversedAdjacentPairCount: Int
        public let exactPlateauAdjacentPairCount: Int
        public let nonFiniteAdjacentPairCount: Int
        public let strictReferenceOrderPreserved: Bool

        public init(
            expectedAdjacentPairCount: Int,
            comparedAdjacentPairCount: Int,
            reversedAdjacentPairCount: Int,
            exactPlateauAdjacentPairCount: Int,
            nonFiniteAdjacentPairCount: Int
        ) {
            self.expectedAdjacentPairCount = expectedAdjacentPairCount
            self.comparedAdjacentPairCount = comparedAdjacentPairCount
            self.reversedAdjacentPairCount = reversedAdjacentPairCount
            self.exactPlateauAdjacentPairCount = exactPlateauAdjacentPairCount
            self.nonFiniteAdjacentPairCount = nonFiniteAdjacentPairCount
            strictReferenceOrderPreserved = comparedAdjacentPairCount == expectedAdjacentPairCount
                && reversedAdjacentPairCount == 0
                && exactPlateauAdjacentPairCount == 0
                && nonFiniteAdjacentPairCount == 0
        }
    }

    public struct NeutralToneSummary: Codable, Equatable, Sendable {
        public let columnID: String
        public let main: NeutralToneTargetSummary
        public let noritsu: NeutralToneTargetSummary
        public let fuji: NeutralToneTargetSummary

        public init(
            columnID: String,
            main: NeutralToneTargetSummary,
            noritsu: NeutralToneTargetSummary,
            fuji: NeutralToneTargetSummary
        ) {
            self.columnID = columnID
            self.main = main
            self.noritsu = noritsu
            self.fuji = fuji
        }
    }

    public struct ExtendedRangeSummary: Codable, Equatable, Sendable {
        public let inputExcursionPatchCount: Int
        public let mainExcursionDirectionPreservedPatchCount: Int
        public let noritsuExcursionDirectionPreservedPatchCount: Int
        public let fujiExcursionDirectionPreservedPatchCount: Int
        public let noritsuPatchMeanRGBEqualToMainPatchCount: Int
        public let fujiPatchMeanRGBEqualToMainPatchCount: Int

        public init(
            inputExcursionPatchCount: Int,
            mainExcursionDirectionPreservedPatchCount: Int,
            noritsuExcursionDirectionPreservedPatchCount: Int,
            fujiExcursionDirectionPreservedPatchCount: Int,
            noritsuPatchMeanRGBEqualToMainPatchCount: Int,
            fujiPatchMeanRGBEqualToMainPatchCount: Int
        ) {
            self.inputExcursionPatchCount = inputExcursionPatchCount
            self.mainExcursionDirectionPreservedPatchCount = mainExcursionDirectionPreservedPatchCount
            self.noritsuExcursionDirectionPreservedPatchCount = noritsuExcursionDirectionPreservedPatchCount
            self.fujiExcursionDirectionPreservedPatchCount = fujiExcursionDirectionPreservedPatchCount
            self.noritsuPatchMeanRGBEqualToMainPatchCount =
                noritsuPatchMeanRGBEqualToMainPatchCount
            self.fujiPatchMeanRGBEqualToMainPatchCount =
                fujiPatchMeanRGBEqualToMainPatchCount
        }
    }

    public struct DeltaDistribution: Codable, Equatable, Sendable {
        public let finitePatchCount: Int
        public let medianDeltaE00: Double?
        public let p95DeltaE00: Double?
        public let maximumDeltaE00: Double?

        public init(
            finitePatchCount: Int,
            medianDeltaE00: Double?,
            p95DeltaE00: Double?,
            maximumDeltaE00: Double?
        ) {
            self.finitePatchCount = finitePatchCount
            self.medianDeltaE00 = medianDeltaE00
            self.p95DeltaE00 = p95DeltaE00
            self.maximumDeltaE00 = maximumDeltaE00
        }
    }

    public struct RelativeDeltaSummary: Codable, Equatable, Sendable {
        /// All 264 reference patches. Extended-linear reference colors are bounded by the synthetic
        /// fixed print-response forward model before scanner-relative grading.
        public let noritsuFromMain: DeltaDistribution
        public let fujiFromMain: DeltaDistribution
        public let noritsuFuji: DeltaDistribution
        /// Synthetic input patches wholly inside the LUT's declared [0, 1] working cube.
        public let unitCubeInputPatchCount: Int
        public let noritsuFromMainWithinUnitCube: DeltaDistribution
        public let fujiFromMainWithinUnitCube: DeltaDistribution
        public let noritsuFujiWithinUnitCube: DeltaDistribution

        public init(
            noritsuFromMain: DeltaDistribution,
            fujiFromMain: DeltaDistribution,
            noritsuFuji: DeltaDistribution,
            unitCubeInputPatchCount: Int,
            noritsuFromMainWithinUnitCube: DeltaDistribution,
            fujiFromMainWithinUnitCube: DeltaDistribution,
            noritsuFujiWithinUnitCube: DeltaDistribution
        ) {
            self.noritsuFromMain = noritsuFromMain
            self.fujiFromMain = fujiFromMain
            self.noritsuFuji = noritsuFuji
            self.unitCubeInputPatchCount = unitCubeInputPatchCount
            self.noritsuFromMainWithinUnitCube = noritsuFromMainWithinUnitCube
            self.fujiFromMainWithinUnitCube = fujiFromMainWithinUnitCube
            self.noritsuFujiWithinUnitCube = noritsuFujiWithinUnitCube
        }
    }

    public struct Summary: Codable, Equatable, Sendable {
        public let totalPatchCount: Int
        public let validPatchCount: Int
        public let nonFinitePatchCount: Int
        public let repeatability: RepeatabilitySummary
        public let neutralTone: NeutralToneSummary
        public let extendedRange: ExtendedRangeSummary
        public let relativeDeltaE00: RelativeDeltaSummary

        public init(
            totalPatchCount: Int,
            validPatchCount: Int,
            nonFinitePatchCount: Int,
            repeatability: RepeatabilitySummary,
            neutralTone: NeutralToneSummary,
            extendedRange: ExtendedRangeSummary,
            relativeDeltaE00: RelativeDeltaSummary
        ) {
            self.totalPatchCount = totalPatchCount
            self.validPatchCount = validPatchCount
            self.nonFinitePatchCount = nonFinitePatchCount
            self.repeatability = repeatability
            self.neutralTone = neutralTone
            self.extendedRange = extendedRange
            self.relativeDeltaE00 = relativeDeltaE00
        }
    }

    public let schemaVersion: Int
    public let benchmarkKind: String
    public let evidenceClass: EvidenceClass
    public let qualityDecision: QualityDecision
    public let reference: ReferenceIdentity
    public let syntheticModel: SyntheticModel
    public let profileBundle: ScannerProfileBundleIdentity
    public let relativeProfilePairs: [RelativeProfilePairIdentity]
    public let patches: [Patch]
    public let summary: Summary

    public init(
        schemaVersion: Int = 2,
        benchmarkKind: String,
        evidenceClass: EvidenceClass = .syntheticModel,
        qualityDecision: QualityDecision = .notEvaluated,
        reference: ReferenceIdentity,
        syntheticModel: SyntheticModel,
        profileBundle: ScannerProfileBundleIdentity,
        relativeProfilePairs: [RelativeProfilePairIdentity],
        patches: [Patch],
        summary: Summary
    ) {
        self.schemaVersion = schemaVersion
        self.benchmarkKind = benchmarkKind
        self.evidenceClass = evidenceClass
        self.qualityDecision = qualityDecision
        self.reference = reference
        self.syntheticModel = syntheticModel
        self.profileBundle = profileBundle
        self.relativeProfilePairs = relativeProfilePairs
        self.patches = patches
        self.summary = summary
    }
}

public enum ScannerRelativeIT8BenchmarkError: Error, Equatable, LocalizedError {
    case invalidExpectedReferenceSHA256(String)
    case referenceSHA256Mismatch(expected: String, actual: String)
    case referenceParseFailed(String)
    case invalidReferencePatchCount(expected: Int, actual: Int)
    case unexpectedReferencePatch(String)
    case missingReferencePatch(String)
    case nonFiniteReferencePatch(String)
    case nonFiniteSyntheticInput(String)
    case scannerProfileBundleUnavailable
    case scannerRelativePairUnavailable
    case renderingUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExpectedReferenceSHA256(let value):
            return "invalid expected reference SHA-256: \(value)"
        case .referenceSHA256Mismatch(let expected, let actual):
            return "reference SHA-256 mismatch (expected \(expected), actual \(actual))"
        case .referenceParseFailed(let reason):
            return "cannot parse IT8 reference: \(reason)"
        case .invalidReferencePatchCount(let expected, let actual):
            return "IT8 reference patch count mismatch (expected \(expected), actual \(actual))"
        case .unexpectedReferencePatch(let id):
            return "IT8 reference contains an unexpected patch: \(id)"
        case .missingReferencePatch(let id):
            return "IT8 reference is missing required patch: \(id)"
        case .nonFiniteReferencePatch(let id):
            return "IT8 reference contains a non-finite Lab patch: \(id)"
        case .nonFiniteSyntheticInput(let id):
            return "synthetic negative model produced a non-finite patch: \(id)"
        case .scannerProfileBundleUnavailable:
            return "scanner profile bundle is missing or failed complete hash validation"
        case .scannerRelativePairUnavailable:
            return "scanner profile bundle has no eligible NORITSU/FUJI color-negative relative pair"
        case .renderingUnavailable(let reason):
            return "scanner-relative IT8 rendering is unavailable: \(reason)"
        }
    }
}
