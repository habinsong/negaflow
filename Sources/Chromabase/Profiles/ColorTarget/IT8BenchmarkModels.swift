import Foundation

public struct IT8BenchmarkManifest: Codable, Equatable, Sendable {
    public enum EvidenceClass: String, Codable, Sendable {
        case algorithmRegression
        case deviceCharacterization
        case syntheticModel
    }

    public struct Image: Codable, Equatable, Sendable {
        public var path: String
        public var sha256: String
        public var width: Int
        public var height: Int
        public var expectedICCProfileName: String
        public var expectedICCProfileSHA256: String?

        public init(
            path: String,
            sha256: String,
            width: Int,
            height: Int,
            expectedICCProfileName: String,
            expectedICCProfileSHA256: String? = nil
        ) {
            self.path = path
            self.sha256 = sha256
            self.width = width
            self.height = height
            self.expectedICCProfileName = expectedICCProfileName
            self.expectedICCProfileSHA256 = expectedICCProfileSHA256
        }
    }

    public struct Reference: Codable, Equatable, Sendable {
        public enum Illuminant: String, Codable, Sendable {
            case d50 = "D50"
        }

        public enum Observer: String, Codable, Sendable {
            case cie1931TwoDegree = "CIE1931_2deg"
        }

        public var path: String
        public var sha256: String
        public var illuminant: Illuminant
        public var observer: Observer

        public init(
            path: String,
            sha256: String,
            illuminant: Illuminant = .d50,
            observer: Observer = .cie1931TwoDegree
        ) {
            self.path = path
            self.sha256 = sha256
            self.illuminant = illuminant
            self.observer = observer
        }
    }

    public struct Layout: Codable, Equatable, Sendable {
        public struct TopLeftPixelRect: Codable, Equatable, Sendable {
            public var x: Double
            public var y: Double
            public var width: Double
            public var height: Double

            public init(x: Double, y: Double, width: Double, height: Double) {
                self.x = x
                self.y = y
                self.width = width
                self.height = height
            }
        }

        public var rows: Int
        public var columns: Int
        public var gridRectTopLeftPixels: TopLeftPixelRect
        public var roiInsetFraction: Double

        public init(
            rows: Int,
            columns: Int,
            gridRectTopLeftPixels: TopLeftPixelRect,
            roiInsetFraction: Double
        ) {
            self.rows = rows
            self.columns = columns
            self.gridRectTopLeftPixels = gridRectTopLeftPixels
            self.roiInsetFraction = roiInsetFraction
        }
    }

    public struct Measurement: Codable, Equatable, Sendable {
        public enum SamplerVersion: String, Codable, Sendable {
            case centerMeanV1 = "center-mean-v1"
        }

        public enum RenderingIntent: String, Codable, Sendable {
            case relativeColorimetric
        }

        public struct PhysicalTargetIdentity: Codable, Equatable, Sendable {
            public var manufacturer: String
            public var material: String
            public var serial: String
            public var batchMetadataKey: String
            public var batchValue: String

            public init(
                manufacturer: String,
                material: String,
                serial: String,
                batchMetadataKey: String,
                batchValue: String
            ) {
                self.manufacturer = manufacturer
                self.material = material
                self.serial = serial
                self.batchMetadataKey = batchMetadataKey
                self.batchValue = batchValue
            }
        }

        public var samplerVersion: SamplerVersion
        public var renderingIntent: RenderingIntent
        public var physicalTargetIdentity: PhysicalTargetIdentity?

        public init(
            samplerVersion: SamplerVersion = .centerMeanV1,
            renderingIntent: RenderingIntent = .relativeColorimetric,
            physicalTargetIdentity: PhysicalTargetIdentity? = nil
        ) {
            self.samplerVersion = samplerVersion
            self.renderingIntent = renderingIntent
            self.physicalTargetIdentity = physicalTargetIdentity
        }
    }

    public var schemaVersion: Int
    public var evidenceClass: EvidenceClass
    public var targetStandard: String
    public var targetID: String
    public var batchID: String
    public var referenceKind: String
    public var image: Image
    public var reference: Reference
    public var layout: Layout
    public var measurement: Measurement

    public init(
        schemaVersion: Int = 1,
        evidenceClass: EvidenceClass,
        targetStandard: String,
        targetID: String,
        batchID: String,
        referenceKind: String,
        image: Image,
        reference: Reference,
        layout: Layout,
        measurement: Measurement = Measurement()
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceClass = evidenceClass
        self.targetStandard = targetStandard
        self.targetID = targetID
        self.batchID = batchID
        self.referenceKind = referenceKind
        self.image = image
        self.reference = reference
        self.layout = layout
        self.measurement = measurement
    }
}

public struct IT8BenchmarkReport: Codable, Equatable, Sendable {
    public enum QualityDecision: String, Codable, Sendable {
        case notEvaluated
    }

    public enum SourceCodeEndpointClipping: String, Codable, Sendable {
        case notMeasured
    }

    public struct RGB: Codable, Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double

        public init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public struct ChannelCounts: Codable, Equatable, Sendable {
        public var r: Int
        public var g: Int
        public var b: Int

        public init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public struct PixelRect: Codable, Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct ImageIdentity: Codable, Equatable, Sendable {
        public var path: String
        public var sha256: String
        public var width: Int
        public var height: Int
        public var iccProfileName: String
        public var iccProfileSHA256: String

        public init(
            path: String,
            sha256: String,
            width: Int,
            height: Int,
            iccProfileName: String,
            iccProfileSHA256: String
        ) {
            self.path = path
            self.sha256 = sha256
            self.width = width
            self.height = height
            self.iccProfileName = iccProfileName
            self.iccProfileSHA256 = iccProfileSHA256
        }
    }

    public struct ReferenceIdentity: Codable, Equatable, Sendable {
        public var path: String
        public var sha256: String
        public var illuminant: IT8BenchmarkManifest.Reference.Illuminant
        public var observer: IT8BenchmarkManifest.Reference.Observer
        public var usedPatchCount: Int
        public var unusedReferencePatchCount: Int

        public init(
            path: String,
            sha256: String,
            illuminant: IT8BenchmarkManifest.Reference.Illuminant,
            observer: IT8BenchmarkManifest.Reference.Observer,
            usedPatchCount: Int,
            unusedReferencePatchCount: Int
        ) {
            self.path = path
            self.sha256 = sha256
            self.illuminant = illuminant
            self.observer = observer
            self.usedPatchCount = usedPatchCount
            self.unusedReferencePatchCount = unusedReferencePatchCount
        }
    }

    public struct Provenance: Codable, Equatable, Sendable {
        public enum PhysicalTargetIdentityEvidence: String, Codable, Sendable {
            case notVerified
            case operatorRecordedMeasurementIdentityMatchedReferenceHeader
        }

        public enum ReferenceConditionEvidence: String, Codable, Sendable {
            case evaluatorD50TwoDegreeConversionContractOnly
            case partialReferenceHeaderMatchAndEvaluatorConversionContract
            case referenceHeaderMatchAndEvaluatorConversionContract
        }

        public enum RenderingIntentEvidence: String, Codable, Sendable {
            case manifestDeclarationNotControlledByEvaluator
        }

        public var physicalTargetIdentity: PhysicalTargetIdentityEvidence
        public var referenceConditions: ReferenceConditionEvidence
        public var renderingIntent: RenderingIntentEvidence

        public init(
            physicalTargetIdentity: PhysicalTargetIdentityEvidence,
            referenceConditions: ReferenceConditionEvidence,
            renderingIntent: RenderingIntentEvidence
        ) {
            self.physicalTargetIdentity = physicalTargetIdentity
            self.referenceConditions = referenceConditions
            self.renderingIntent = renderingIntent
        }
    }

    public struct WorkingSpaceDiagnostics: Codable, Equatable, Sendable {
        public var atOrBelowZeroFractionByChannel: RGB
        public var atOrAboveOneFractionByChannel: RGB
        public var anyAtOrBelowZeroPixelFraction: Double
        public var anyAtOrAboveOnePixelFraction: Double
        public var nonFiniteValueCountByChannel: ChannelCounts
        public var anyNonFinitePixelCount: Int
        public var anyNonFinitePixelFraction: Double

        public init(
            atOrBelowZeroFractionByChannel: RGB,
            atOrAboveOneFractionByChannel: RGB,
            anyAtOrBelowZeroPixelFraction: Double,
            anyAtOrAboveOnePixelFraction: Double,
            nonFiniteValueCountByChannel: ChannelCounts,
            anyNonFinitePixelCount: Int,
            anyNonFinitePixelFraction: Double
        ) {
            self.atOrBelowZeroFractionByChannel = atOrBelowZeroFractionByChannel
            self.atOrAboveOneFractionByChannel = atOrAboveOneFractionByChannel
            self.anyAtOrBelowZeroPixelFraction = anyAtOrBelowZeroPixelFraction
            self.anyAtOrAboveOnePixelFraction = anyAtOrAboveOnePixelFraction
            self.nonFiniteValueCountByChannel = nonFiniteValueCountByChannel
            self.anyNonFinitePixelCount = anyNonFinitePixelCount
            self.anyNonFinitePixelFraction = anyNonFinitePixelFraction
        }
    }

    public struct Delta: Codable, Equatable, Sendable {
        public var l: Double
        public var a: Double
        public var b: Double
        public var e00: Double

        public init(l: Double, a: Double, b: Double, e00: Double) {
            self.l = l
            self.a = a
            self.b = b
            self.e00 = e00
        }
    }

    public enum PatchFlag: String, Codable, Sendable {
        case containsWorkingValueAtOrBelowZero
        case containsWorkingValueAtOrAboveOne
        case containsNonFiniteValue
    }

    public struct Patch: Codable, Equatable, Sendable {
        public var id: String
        public var referenceID: String
        public var row: Int
        public var column: Int
        public var roiTopLeftPixels: PixelRect
        public var roiCIImagePixels: PixelRect
        public var pixelCount: Int
        public var finitePixelCount: Int
        public var linearRGBMean: RGB?
        public var linearRGBStandardDeviation: RGB?
        public var measuredLabD50: ColorTargetLab?
        public var referenceLabD50: ColorTargetLab
        public var delta: Delta?
        public var workingSpaceDiagnostics: WorkingSpaceDiagnostics
        public var flags: [PatchFlag]

        public init(
            id: String,
            referenceID: String,
            row: Int,
            column: Int,
            roiTopLeftPixels: PixelRect,
            roiCIImagePixels: PixelRect,
            pixelCount: Int,
            finitePixelCount: Int,
            linearRGBMean: RGB?,
            linearRGBStandardDeviation: RGB?,
            measuredLabD50: ColorTargetLab?,
            referenceLabD50: ColorTargetLab,
            delta: Delta?,
            workingSpaceDiagnostics: WorkingSpaceDiagnostics,
            flags: [PatchFlag]
        ) {
            self.id = id
            self.referenceID = referenceID
            self.row = row
            self.column = column
            self.roiTopLeftPixels = roiTopLeftPixels
            self.roiCIImagePixels = roiCIImagePixels
            self.pixelCount = pixelCount
            self.finitePixelCount = finitePixelCount
            self.linearRGBMean = linearRGBMean
            self.linearRGBStandardDeviation = linearRGBStandardDeviation
            self.measuredLabD50 = measuredLabD50
            self.referenceLabD50 = referenceLabD50
            self.delta = delta
            self.workingSpaceDiagnostics = workingSpaceDiagnostics
            self.flags = flags
        }
    }

    public struct Summary: Codable, Equatable, Sendable {
        public var validPatchCount: Int
        public var medianDeltaE00: Double?
        public var p95DeltaE00: Double?
        public var maximumDeltaE00: Double?
        public var workingSpaceExcursionPatchCount: Int

        public init(
            validPatchCount: Int,
            medianDeltaE00: Double?,
            p95DeltaE00: Double?,
            maximumDeltaE00: Double?,
            workingSpaceExcursionPatchCount: Int
        ) {
            self.validPatchCount = validPatchCount
            self.medianDeltaE00 = medianDeltaE00
            self.p95DeltaE00 = p95DeltaE00
            self.maximumDeltaE00 = maximumDeltaE00
            self.workingSpaceExcursionPatchCount = workingSpaceExcursionPatchCount
        }
    }

    public var schemaVersion: Int
    public var manifestSHA256: String
    public var qualityDecision: QualityDecision
    public var sourceCodeEndpointClipping: SourceCodeEndpointClipping
    public var evidenceClass: IT8BenchmarkManifest.EvidenceClass
    public var targetStandard: String
    public var targetID: String
    public var batchID: String
    public var referenceKind: String
    public var image: ImageIdentity
    public var reference: ReferenceIdentity
    public var layout: IT8BenchmarkManifest.Layout
    public var measurement: IT8BenchmarkManifest.Measurement
    public var provenance: Provenance
    public var patches: [Patch]
    public var summary: Summary

    public init(
        schemaVersion: Int = 2,
        manifestSHA256: String,
        qualityDecision: QualityDecision = .notEvaluated,
        sourceCodeEndpointClipping: SourceCodeEndpointClipping = .notMeasured,
        evidenceClass: IT8BenchmarkManifest.EvidenceClass,
        targetStandard: String,
        targetID: String,
        batchID: String,
        referenceKind: String,
        image: ImageIdentity,
        reference: ReferenceIdentity,
        layout: IT8BenchmarkManifest.Layout,
        measurement: IT8BenchmarkManifest.Measurement,
        provenance: Provenance,
        patches: [Patch],
        summary: Summary
    ) {
        self.schemaVersion = schemaVersion
        self.manifestSHA256 = manifestSHA256
        self.qualityDecision = qualityDecision
        self.sourceCodeEndpointClipping = sourceCodeEndpointClipping
        self.evidenceClass = evidenceClass
        self.targetStandard = targetStandard
        self.targetID = targetID
        self.batchID = batchID
        self.referenceKind = referenceKind
        self.image = image
        self.reference = reference
        self.layout = layout
        self.measurement = measurement
        self.provenance = provenance
        self.patches = patches
        self.summary = summary
    }
}

public enum IT8BenchmarkError: Error, Equatable, LocalizedError {
    case invalidManifest(String)
    case manifestPathEscapes(String)
    case unreadableFile(String)
    case fileHashMismatch(kind: String, expected: String, actual: String)
    case imageLoadFailed(String)
    case imageMetadataMissing(String)
    case imageDimensionMismatch(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case iccProfileNameMismatch(expected: String, actual: String)
    case iccProfileHashMismatch(expected: String, actual: String)
    case referenceParseFailed(String)
    case physicalTargetIdentityMismatch(field: String, expected: String, actual: String?)
    case referenceConditionMismatch(field: String, expected: String, actual: String)
    case missingReferencePatch(String)
    case duplicateReferencePatch(String)
    case invalidPatchIdentifier(String)
    case invalidPatchROI(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason):
            return "invalid IT8 manifest: \(reason)"
        case .manifestPathEscapes(let path):
            return "manifest-relative path escapes its directory: \(path)"
        case .unreadableFile(let path):
            return "cannot read required file: \(path)"
        case .fileHashMismatch(let kind, let expected, let actual):
            return "\(kind) SHA-256 mismatch (expected \(expected), actual \(actual))"
        case .imageLoadFailed(let path):
            return "cannot decode IT8 image: \(path)"
        case .imageMetadataMissing(let field):
            return "IT8 image metadata is missing: \(field)"
        case .imageDimensionMismatch(let expectedWidth, let expectedHeight, let actualWidth, let actualHeight):
            return "IT8 image dimensions mismatch (expected \(expectedWidth)x\(expectedHeight), actual \(actualWidth)x\(actualHeight))"
        case .iccProfileNameMismatch(let expected, let actual):
            return "embedded ICC profile name mismatch (expected \(expected), actual \(actual))"
        case .iccProfileHashMismatch(let expected, let actual):
            return "embedded ICC profile SHA-256 mismatch (expected \(expected), actual \(actual))"
        case .referenceParseFailed(let reason):
            return "cannot parse IT8 reference: \(reason)"
        case .physicalTargetIdentityMismatch(let field, let expected, let actual):
            let actualValue = actual ?? "missing"
            return "IT8 physical target identity mismatch for \(field) (expected \(expected), actual \(actualValue))"
        case .referenceConditionMismatch(let field, let expected, let actual):
            return "IT8 reference condition mismatch for \(field) (expected \(expected), actual \(actual))"
        case .missingReferencePatch(let id):
            return "IT8 reference is missing required patch \(id)"
        case .duplicateReferencePatch(let id):
            return "IT8 reference contains duplicate patch \(id)"
        case .invalidPatchIdentifier(let id):
            return "invalid IT8 patch identifier: \(id)"
        case .invalidPatchROI(let id):
            return "IT8 patch ROI is empty or outside the image: \(id)"
        }
    }
}
