import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO

public enum IT8PatchEvaluator {
    public static func evaluate(
        manifestURL: URL,
        imageURLOverride: URL? = nil,
        referenceURLOverride: URL? = nil
    ) throws -> IT8BenchmarkReport {
        let manifestFile = manifestURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifestData = try readData(from: manifestFile)
        let manifestHash = sha256Data(manifestData)
        try validateManifestJSONShape(manifestData)

        let manifest: IT8BenchmarkManifest
        do {
            manifest = try JSONDecoder().decode(IT8BenchmarkManifest.self, from: manifestData)
        } catch {
            throw IT8BenchmarkError.invalidManifest(String(describing: error))
        }
        try validate(manifest)

        let manifestDirectory = manifestFile.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let imageURL = try resolvedInputURL(
            override: imageURLOverride,
            manifestPath: manifest.image.path,
            manifestDirectory: manifestDirectory
        )
        let referenceURL = try resolvedInputURL(
            override: referenceURLOverride,
            manifestPath: manifest.reference.path,
            manifestDirectory: manifestDirectory
        )

        let imageData = try readData(from: imageURL)
        let imageHash = sha256Data(imageData)
        guard imageHash == manifest.image.sha256 else {
            throw IT8BenchmarkError.fileHashMismatch(
                kind: "image",
                expected: manifest.image.sha256,
                actual: imageHash
            )
        }
        let referenceData = try readData(from: referenceURL)
        let referenceHash = sha256Data(referenceData)
        guard referenceHash == manifest.reference.sha256 else {
            throw IT8BenchmarkError.fileHashMismatch(
                kind: "reference",
                expected: manifest.reference.sha256,
                actual: referenceHash
            )
        }

        let decodedImage = try decodeImage(imageData, path: imageURL.path)
        let metadata = decodedImage.metadata
        guard metadata.profileName == manifest.image.expectedICCProfileName else {
            throw IT8BenchmarkError.iccProfileNameMismatch(
                expected: manifest.image.expectedICCProfileName,
                actual: metadata.profileName
            )
        }
        if let expectedICC = manifest.image.expectedICCProfileSHA256,
           expectedICC != metadata.profileSHA256 {
            throw IT8BenchmarkError.iccProfileHashMismatch(
                expected: expectedICC,
                actual: metadata.profileSHA256
            )
        }

        let loaded = decodedImage.image
        let sourceExtent = loaded.extent
        guard sourceExtent.minX.isFinite,
              sourceExtent.minY.isFinite,
              sourceExtent.width.isFinite,
              sourceExtent.height.isFinite,
              sourceExtent.width > 0,
              sourceExtent.height > 0,
              sourceExtent.width.rounded() == sourceExtent.width,
              sourceExtent.height.rounded() == sourceExtent.height else {
            throw IT8BenchmarkError.imageLoadFailed(imageURL.path)
        }
        let actualWidth = Int(sourceExtent.width)
        let actualHeight = Int(sourceExtent.height)
        guard actualWidth == manifest.image.width,
              actualHeight == manifest.image.height else {
            throw IT8BenchmarkError.imageDimensionMismatch(
                expectedWidth: manifest.image.width,
                expectedHeight: manifest.image.height,
                actualWidth: actualWidth,
                actualHeight: actualHeight
            )
        }
        let image = sourceExtent.origin == .zero
            ? loaded
            : loaded.transformed(by: CGAffineTransform(
                translationX: -sourceExtent.minX,
                y: -sourceExtent.minY
            ))

        let referenceDocument: IT8ReferenceDocument
        do {
            referenceDocument = try IT8ReferenceParser.parse(referenceData)
        } catch {
            throw IT8BenchmarkError.referenceParseFailed(String(describing: error))
        }
        let physicalTargetIdentityEvidence = try physicalTargetIdentityEvidence(
            manifest: manifest,
            reference: referenceDocument
        )
        let referenceConditionEvidence = try referenceConditionEvidence(
            referenceDocument
        )
        let indexedReference = try indexRequiredPatches(
            referenceDocument,
            rows: manifest.layout.rows,
            columns: manifest.layout.columns
        )

        guard let extendedLinearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw IT8BenchmarkError.imageMetadataMissing("extendedLinearSRGB")
        }
        let context = CIContext(options: [
            .workingColorSpace: extendedLinearSRGB,
            .outputColorSpace: extendedLinearSRGB,
            .workingFormat: CIFormat.RGBAf,
        ])

        var reports: [IT8BenchmarkReport.Patch] = []
        reports.reserveCapacity(manifest.layout.rows * manifest.layout.columns)
        for row in 0..<manifest.layout.rows {
            for column in 0..<manifest.layout.columns {
                let id = patchID(column: column, row: row)
                guard let referencePatch = indexedReference.patches[id] else {
                    throw IT8BenchmarkError.missingReferencePatch(id)
                }
                let roi = try patchROI(
                    manifest.layout,
                    row: row,
                    column: column,
                    imageWidth: actualWidth,
                    imageHeight: actualHeight,
                    id: id
                )
                reports.append(try measure(
                    id: id,
                    row: row,
                    column: column,
                    roi: roi,
                    image: image,
                    reference: referencePatch,
                    context: context,
                    colorSpace: extendedLinearSRGB
                ))
            }
        }

        let validDeltaE = reports.compactMap { patch -> Double? in
            guard patch.finitePixelCount == patch.pixelCount,
                  let value = patch.delta?.e00,
                  value.isFinite else { return nil }
            return value
        }.sorted()
        let workingSpaceExcursionPatchCount = reports.reduce(into: 0) { count, patch in
            if patch.flags.contains(.containsWorkingValueAtOrBelowZero)
                || patch.flags.contains(.containsWorkingValueAtOrAboveOne) {
                count += 1
            }
        }
        let summary = IT8BenchmarkReport.Summary(
            validPatchCount: validDeltaE.count,
            medianDeltaE00: percentile(validDeltaE, fraction: 0.50),
            p95DeltaE00: percentile(validDeltaE, fraction: 0.95),
            maximumDeltaE00: validDeltaE.last,
            workingSpaceExcursionPatchCount: workingSpaceExcursionPatchCount
        )

        return IT8BenchmarkReport(
            manifestSHA256: manifestHash,
            evidenceClass: manifest.evidenceClass,
            targetStandard: manifest.targetStandard,
            targetID: manifest.targetID,
            batchID: manifest.batchID,
            referenceKind: manifest.referenceKind,
            image: IT8BenchmarkReport.ImageIdentity(
                path: imageURL.path,
                sha256: imageHash,
                width: actualWidth,
                height: actualHeight,
                iccProfileName: metadata.profileName,
                iccProfileSHA256: metadata.profileSHA256
            ),
            reference: IT8BenchmarkReport.ReferenceIdentity(
                path: referenceURL.path,
                sha256: referenceHash,
                illuminant: manifest.reference.illuminant,
                observer: manifest.reference.observer,
                usedPatchCount: reports.count,
                unusedReferencePatchCount: indexedReference.unusedPatchCount
            ),
            layout: manifest.layout,
            measurement: manifest.measurement,
            provenance: IT8BenchmarkReport.Provenance(
                physicalTargetIdentity: physicalTargetIdentityEvidence,
                referenceConditions: referenceConditionEvidence,
                renderingIntent: .manifestDeclarationNotControlledByEvaluator
            ),
            patches: reports,
            summary: summary
        )
    }
}

private extension IT8PatchEvaluator {
    struct ImageMetadata {
        let profileName: String
        let profileSHA256: String
    }

    struct DecodedImage {
        let image: CIImage
        let metadata: ImageMetadata
    }

    struct IndexedReference {
        let patches: [String: IT8ReferencePatch]
        let unusedPatchCount: Int
    }

    struct PatchROI {
        let topLeft: IT8BenchmarkReport.PixelRect
        let coreImage: IT8BenchmarkReport.PixelRect
    }

    static func validate(_ manifest: IT8BenchmarkManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw IT8BenchmarkError.invalidManifest("schemaVersion must be 1")
        }
        try requireNonempty(manifest.targetStandard, field: "targetStandard")
        try requireNonempty(manifest.targetID, field: "targetID")
        try requireNonempty(manifest.batchID, field: "batchID")
        try requireNonempty(manifest.referenceKind, field: "referenceKind")
        switch manifest.evidenceClass {
        case .deviceCharacterization:
            guard let identity = manifest.measurement.physicalTargetIdentity else {
                throw IT8BenchmarkError.invalidManifest(
                    "deviceCharacterization requires measurement.physicalTargetIdentity"
                )
            }
            try requireNonempty(
                identity.manufacturer,
                field: "measurement.physicalTargetIdentity.manufacturer"
            )
            try requireNonempty(
                identity.material,
                field: "measurement.physicalTargetIdentity.material"
            )
            try requireNonempty(
                identity.serial,
                field: "measurement.physicalTargetIdentity.serial"
            )
            try requireNonempty(
                identity.batchValue,
                field: "measurement.physicalTargetIdentity.batchValue"
            )
            let batchMetadataKey = identity.batchMetadataKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard ["BATCH", "BATCH_ID", "PROD_DATE"].contains(batchMetadataKey),
                  identity.batchMetadataKey == batchMetadataKey else {
                throw IT8BenchmarkError.invalidManifest(
                    "measurement.physicalTargetIdentity.batchMetadataKey must be BATCH, BATCH_ID, or PROD_DATE"
                )
            }
            guard manifest.targetID == identity.serial else {
                throw IT8BenchmarkError.invalidManifest(
                    "deviceCharacterization targetID must equal measurement.physicalTargetIdentity.serial"
                )
            }
            guard manifest.batchID == identity.batchValue else {
                throw IT8BenchmarkError.invalidManifest(
                    "deviceCharacterization batchID must equal measurement.physicalTargetIdentity.batchValue"
                )
            }
        case .algorithmRegression, .syntheticModel:
            guard manifest.measurement.physicalTargetIdentity == nil else {
                throw IT8BenchmarkError.invalidManifest(
                    "measurement.physicalTargetIdentity is reserved for deviceCharacterization"
                )
            }
        }
        try validateRelativePath(manifest.image.path)
        try validateRelativePath(manifest.reference.path)
        try validateSHA256(manifest.image.sha256, field: "image.sha256")
        try validateSHA256(manifest.reference.sha256, field: "reference.sha256")
        if let hash = manifest.image.expectedICCProfileSHA256 {
            try validateSHA256(hash, field: "image.expectedICCProfileSHA256")
        }
        try requireNonempty(
            manifest.image.expectedICCProfileName,
            field: "image.expectedICCProfileName"
        )
        guard manifest.image.width > 0, manifest.image.height > 0 else {
            throw IT8BenchmarkError.invalidManifest("image dimensions must be positive")
        }
        guard manifest.layout.rows > 0, manifest.layout.columns > 0,
              manifest.layout.rows <= Int.max / manifest.layout.columns else {
            throw IT8BenchmarkError.invalidManifest("layout dimensions are invalid")
        }
        let grid = manifest.layout.gridRectTopLeftPixels
        guard grid.x.isFinite, grid.y.isFinite, grid.width.isFinite, grid.height.isFinite,
              grid.x >= 0, grid.y >= 0, grid.width > 0, grid.height > 0,
              grid.x + grid.width <= Double(manifest.image.width),
              grid.y + grid.height <= Double(manifest.image.height) else {
            throw IT8BenchmarkError.invalidManifest("layout grid is outside the image")
        }
        guard manifest.layout.roiInsetFraction.isFinite,
              manifest.layout.roiInsetFraction >= 0,
              manifest.layout.roiInsetFraction < 0.5 else {
            throw IT8BenchmarkError.invalidManifest("roiInsetFraction must be in [0, 0.5)")
        }
        let retainedFraction = 1 - 2 * manifest.layout.roiInsetFraction
        guard grid.width / Double(manifest.layout.columns) * retainedFraction >= 1,
              grid.height / Double(manifest.layout.rows) * retainedFraction >= 1 else {
            throw IT8BenchmarkError.invalidManifest(
                "layout cells are too small for the requested center ROI"
            )
        }
    }

    static func requireNonempty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IT8BenchmarkError.invalidManifest("\(field) must not be empty")
        }
    }

    static func validateSHA256(_ value: String, field: String) throws {
        let prefix = "sha256:"
        guard value.hasPrefix(prefix), value.count == prefix.count + 64 else {
            throw IT8BenchmarkError.invalidManifest("\(field) must be sha256:<64 lowercase hex>")
        }
        let digest = value.dropFirst(prefix.count)
        let valid = digest.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
        guard valid else {
            throw IT8BenchmarkError.invalidManifest("\(field) must be sha256:<64 lowercase hex>")
        }
    }

    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            throw IT8BenchmarkError.manifestPathEscapes(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw IT8BenchmarkError.manifestPathEscapes(path)
        }
    }

    static func resolvedInputURL(
        override: URL?,
        manifestPath: String,
        manifestDirectory: URL
    ) throws -> URL {
        if let override {
            return override.standardizedFileURL.resolvingSymlinksInPath()
        }
        let candidate = manifestDirectory.appendingPathComponent(manifestPath)
            .standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = manifestDirectory.pathComponents
        guard candidate.pathComponents.starts(with: rootComponents),
              candidate.pathComponents.count > rootComponents.count else {
            throw IT8BenchmarkError.manifestPathEscapes(manifestPath)
        }
        return candidate
    }

    static func readData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw IT8BenchmarkError.unreadableFile(url.path)
        }
    }

    static func decodeImage(_ data: Data, path: String) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IT8BenchmarkError.imageLoadFailed(path)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let profileName = properties[kCGImagePropertyProfileName] as? String,
              !profileName.isEmpty,
              let colorSpace = image.colorSpace,
              let profileData = colorSpace.copyICCData() as Data? else {
            throw IT8BenchmarkError.imageMetadataMissing("embedded ICC profile")
        }
        let base = ImageLoader.profileAwareImage(
            image,
            properties: properties,
            untaggedTIFFRole: .standardImage
        )
        let orientation = ImageLoader.exifOrientation(properties)
        return DecodedImage(
            image: orientation == 1 ? base : base.oriented(forExifOrientation: orientation),
            metadata: ImageMetadata(
                profileName: profileName,
                profileSHA256: sha256Data(profileData)
            )
        )
    }

    static func sha256Data(_ data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
    }

    static func physicalTargetIdentityEvidence(
        manifest: IT8BenchmarkManifest,
        reference: IT8ReferenceDocument
    ) throws -> IT8BenchmarkReport.Provenance.PhysicalTargetIdentityEvidence {
        guard manifest.evidenceClass == .deviceCharacterization,
              let identity = manifest.measurement.physicalTargetIdentity else {
            return .notVerified
        }

        let requiredFields = [
            (key: "MANUFACTURER", expected: identity.manufacturer),
            (key: "MATERIAL", expected: identity.material),
            (key: "SERIAL", expected: identity.serial),
            (key: identity.batchMetadataKey, expected: identity.batchValue),
        ]
        for field in requiredFields {
            let actual = reference.metadata[field.key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard actual == field.expected else {
                throw IT8BenchmarkError.physicalTargetIdentityMismatch(
                    field: field.key,
                    expected: field.expected,
                    actual: actual
                )
            }
        }
        return .operatorRecordedMeasurementIdentityMatchedReferenceHeader
    }

    static func referenceConditionEvidence(
        _ reference: IT8ReferenceDocument
    ) throws -> IT8BenchmarkReport.Provenance.ReferenceConditionEvidence {
        let illuminantFields = ["ILLUMINATION_NAME", "ILLUMINANT_NAME", "REFERENCE_ILLUMINANT"]
        let observerFields = ["OBSERVER_ANGLE", "REFERENCE_OBSERVER"]
        let illuminants = illuminantFields.compactMap { key in
            reference.metadata[key].map { (key: key, value: $0) }
        }
        let observers = observerFields.compactMap { key in
            reference.metadata[key].map { (key: key, value: $0) }
        }

        for declaration in illuminants where normalizedCondition(declaration.value) != "D50" {
            throw IT8BenchmarkError.referenceConditionMismatch(
                field: declaration.key,
                expected: "D50",
                actual: declaration.value
            )
        }
        let acceptedObservers: Set<String> = [
            "2", "2DEG", "2DEGREE", "2DEGREES", "CIE19312",
            "CIE19312DEG", "CIE19312DEGREE", "CIE19312DEGREES",
        ]
        for declaration in observers
        where !acceptedObservers.contains(normalizedCondition(declaration.value)) {
            throw IT8BenchmarkError.referenceConditionMismatch(
                field: declaration.key,
                expected: "CIE1931_2deg",
                actual: declaration.value
            )
        }

        if !illuminants.isEmpty, !observers.isEmpty {
            return .referenceHeaderMatchAndEvaluatorConversionContract
        }
        if !illuminants.isEmpty || !observers.isEmpty {
            return .partialReferenceHeaderMatchAndEvaluatorConversionContract
        }
        return .evaluatorD50TwoDegreeConversionContractOnly
    }

    static func normalizedCondition(_ value: String) -> String {
        value.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
    }

    static func indexRequiredPatches(
        _ document: IT8ReferenceDocument,
        rows: Int,
        columns: Int
    ) throws -> IndexedReference {
        var requiredIDs = Set<String>()
        requiredIDs.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                requiredIDs.insert(patchID(column: column, row: row))
            }
        }

        var indexed: [String: IT8ReferencePatch] = [:]
        indexed.reserveCapacity(requiredIDs.count)
        for patch in document.patches {
            let normalized = patch.normalizedID
            guard requiredIDs.contains(normalized) else { continue }
            guard indexed[normalized] == nil else {
                throw IT8BenchmarkError.duplicateReferencePatch(normalized)
            }
            guard patch.lab.l.isFinite, patch.lab.a.isFinite, patch.lab.b.isFinite else {
                throw IT8BenchmarkError.referenceParseFailed(
                    "patch \(patch.id) contains non-finite Lab data"
                )
            }
            indexed[normalized] = patch
        }

        for id in requiredIDs where indexed[id] == nil {
            throw IT8BenchmarkError.missingReferencePatch(id)
        }
        return IndexedReference(
            patches: indexed,
            unusedPatchCount: document.patches.count - indexed.count
        )
    }

    static func patchID(column: Int, row: Int) -> String {
        var value = row + 1
        var letters = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar(65 + value % 26)!
            letters.insert(Character(scalar), at: letters.startIndex)
            value /= 26
        }
        return letters + String(column + 1)
    }

    static func patchROI(
        _ layout: IT8BenchmarkManifest.Layout,
        row: Int,
        column: Int,
        imageWidth: Int,
        imageHeight: Int,
        id: String
    ) throws -> PatchROI {
        let grid = layout.gridRectTopLeftPixels
        let cellWidth = grid.width / Double(layout.columns)
        let cellHeight = grid.height / Double(layout.rows)
        let insetX = cellWidth * layout.roiInsetFraction
        let insetY = cellHeight * layout.roiInsetFraction

        let left = Int(ceil(grid.x + Double(column) * cellWidth + insetX))
        let right = Int(floor(grid.x + Double(column + 1) * cellWidth - insetX))
        let top = Int(ceil(grid.y + Double(row) * cellHeight + insetY))
        let bottom = Int(floor(grid.y + Double(row + 1) * cellHeight - insetY))
        guard left >= 0, top >= 0, right <= imageWidth, bottom <= imageHeight,
              right > left, bottom > top else {
            throw IT8BenchmarkError.invalidPatchROI(id)
        }

        let width = right - left
        let height = bottom - top
        return PatchROI(
            topLeft: IT8BenchmarkReport.PixelRect(
                x: left,
                y: top,
                width: width,
                height: height
            ),
            coreImage: IT8BenchmarkReport.PixelRect(
                x: left,
                y: imageHeight - bottom,
                width: width,
                height: height
            )
        )
    }

    static func measure(
        id: String,
        row: Int,
        column: Int,
        roi: PatchROI,
        image: CIImage,
        reference: IT8ReferencePatch,
        context: CIContext,
        colorSpace: CGColorSpace
    ) throws -> IT8BenchmarkReport.Patch {
        let pixelCount = roi.coreImage.width * roi.coreImage.height
        guard pixelCount > 0 else { throw IT8BenchmarkError.invalidPatchROI(id) }
        var pixels = [Float](repeating: 0, count: pixelCount * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: roi.coreImage.width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(
                x: roi.coreImage.x,
                y: roi.coreImage.y,
                width: roi.coreImage.width,
                height: roi.coreImage.height
            ),
            format: .RGBAf,
            colorSpace: colorSpace
        )

        var runningMean = SIMD3<Double>(repeating: 0)
        var runningM2 = SIMD3<Double>(repeating: 0)
        var finitePixelCount = 0
        var lowCounts = SIMD3<Int>(repeating: 0)
        var highCounts = SIMD3<Int>(repeating: 0)
        var nonFiniteCounts = SIMD3<Int>(repeating: 0)
        var anyLowCount = 0
        var anyHighCount = 0
        var anyNonFiniteCount = 0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = SIMD3<Double>(
                Double(pixels[offset]),
                Double(pixels[offset + 1]),
                Double(pixels[offset + 2])
            )
            var anyLow = false
            var anyHigh = false
            var anyNonFinite = false
            for channel in 0..<3 {
                let value = rgb[channel]
                if !value.isFinite {
                    nonFiniteCounts[channel] += 1
                    anyNonFinite = true
                } else {
                    if value <= 0 {
                        lowCounts[channel] += 1
                        anyLow = true
                    }
                    if value >= 1 {
                        highCounts[channel] += 1
                        anyHigh = true
                    }
                }
            }
            if anyLow { anyLowCount += 1 }
            if anyHigh { anyHighCount += 1 }
            if anyNonFinite {
                anyNonFiniteCount += 1
            } else {
                finitePixelCount += 1
                let delta = rgb - runningMean
                runningMean += delta / Double(finitePixelCount)
                let deltaFromUpdatedMean = rgb - runningMean
                runningM2 += delta * deltaFromUpdatedMean
            }
        }

        let denominator = Double(pixelCount)
        let lowFractions = SIMD3<Double>(
            Double(lowCounts.x) / denominator,
            Double(lowCounts.y) / denominator,
            Double(lowCounts.z) / denominator
        )
        let highFractions = SIMD3<Double>(
            Double(highCounts.x) / denominator,
            Double(highCounts.y) / denominator,
            Double(highCounts.z) / denominator
        )
        let workingSpaceDiagnostics = IT8BenchmarkReport.WorkingSpaceDiagnostics(
            atOrBelowZeroFractionByChannel: rgb(lowFractions),
            atOrAboveOneFractionByChannel: rgb(highFractions),
            anyAtOrBelowZeroPixelFraction: Double(anyLowCount) / denominator,
            anyAtOrAboveOnePixelFraction: Double(anyHighCount) / denominator,
            nonFiniteValueCountByChannel: IT8BenchmarkReport.ChannelCounts(
                r: nonFiniteCounts.x,
                g: nonFiniteCounts.y,
                b: nonFiniteCounts.z
            ),
            anyNonFinitePixelCount: anyNonFiniteCount,
            anyNonFinitePixelFraction: Double(anyNonFiniteCount) / denominator
        )

        var flags: [IT8BenchmarkReport.PatchFlag] = []
        if anyLowCount > 0 { flags.append(.containsWorkingValueAtOrBelowZero) }
        if anyHighCount > 0 { flags.append(.containsWorkingValueAtOrAboveOne) }
        if anyNonFiniteCount > 0 { flags.append(.containsNonFiniteValue) }

        var meanReport: IT8BenchmarkReport.RGB?
        var standardDeviationReport: IT8BenchmarkReport.RGB?
        var measuredLab: ColorTargetLab?
        var delta: IT8BenchmarkReport.Delta?
        if finitePixelCount > 0 {
            let count = Double(finitePixelCount)
            let mean = runningMean
            let rawVariance = runningM2 / count
            let variance = SIMD3<Double>(
                max(0, rawVariance.x),
                max(0, rawVariance.y),
                max(0, rawVariance.z)
            )
            let standardDeviation = SIMD3<Double>(
                sqrt(variance.x),
                sqrt(variance.y),
                sqrt(variance.z)
            )
            let lab = ColorTargetColorimetry.linearSRGBToLabD50(mean)
            let e00 = ColorTargetColorimetry.deltaE2000(lab, reference.lab)
            if mean.x.isFinite, mean.y.isFinite, mean.z.isFinite,
               standardDeviation.x.isFinite,
               standardDeviation.y.isFinite,
               standardDeviation.z.isFinite,
               lab.l.isFinite, lab.a.isFinite, lab.b.isFinite,
               e00.isFinite {
                meanReport = rgb(mean)
                standardDeviationReport = rgb(standardDeviation)
                measuredLab = lab
                delta = IT8BenchmarkReport.Delta(
                    l: lab.l - reference.lab.l,
                    a: lab.a - reference.lab.a,
                    b: lab.b - reference.lab.b,
                    e00: e00
                )
            }
        }

        return IT8BenchmarkReport.Patch(
            id: id,
            referenceID: reference.id,
            row: row + 1,
            column: column + 1,
            roiTopLeftPixels: roi.topLeft,
            roiCIImagePixels: roi.coreImage,
            pixelCount: pixelCount,
            finitePixelCount: finitePixelCount,
            linearRGBMean: meanReport,
            linearRGBStandardDeviation: standardDeviationReport,
            measuredLabD50: measuredLab,
            referenceLabD50: reference.lab,
            delta: delta,
            workingSpaceDiagnostics: workingSpaceDiagnostics,
            flags: flags
        )
    }

    static func rgb(_ vector: SIMD3<Double>) -> IT8BenchmarkReport.RGB {
        IT8BenchmarkReport.RGB(r: vector.x, g: vector.y, b: vector.z)
    }

    static func percentile(_ sorted: [Double], fraction: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        guard sorted.count > 1 else { return sorted[0] }
        let position = min(1, max(0, fraction)) * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func validateManifestJSONShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw IT8BenchmarkError.invalidManifest(String(describing: error))
        }
        guard let root = object as? [String: Any] else {
            throw IT8BenchmarkError.invalidManifest("root must be a JSON object")
        }
        try exactKeys(
            root,
            required: [
                "schemaVersion", "evidenceClass", "targetStandard", "targetID", "batchID",
                "referenceKind", "image", "reference", "layout", "measurement",
            ],
            optional: [],
            field: "root"
        )
        let image = try childObject(root, key: "image")
        try exactKeys(
            image,
            required: ["path", "sha256", "width", "height", "expectedICCProfileName"],
            optional: ["expectedICCProfileSHA256"],
            field: "image"
        )
        let reference = try childObject(root, key: "reference")
        try exactKeys(
            reference,
            required: ["path", "sha256", "illuminant", "observer"],
            optional: [],
            field: "reference"
        )
        let layout = try childObject(root, key: "layout")
        try exactKeys(
            layout,
            required: ["rows", "columns", "gridRectTopLeftPixels", "roiInsetFraction"],
            optional: [],
            field: "layout"
        )
        let grid = try childObject(layout, key: "gridRectTopLeftPixels")
        try exactKeys(
            grid,
            required: ["x", "y", "width", "height"],
            optional: [],
            field: "layout.gridRectTopLeftPixels"
        )
        let measurement = try childObject(root, key: "measurement")
        try exactKeys(
            measurement,
            required: ["samplerVersion", "renderingIntent"],
            optional: ["physicalTargetIdentity"],
            field: "measurement"
        )
        if measurement["physicalTargetIdentity"] != nil {
            let identity = try childObject(measurement, key: "physicalTargetIdentity")
            try exactKeys(
                identity,
                required: [
                    "manufacturer", "material", "serial", "batchMetadataKey", "batchValue",
                ],
                optional: [],
                field: "measurement.physicalTargetIdentity"
            )
        }
    }

    static func childObject(_ parent: [String: Any], key: String) throws -> [String: Any] {
        guard let child = parent[key] as? [String: Any] else {
            throw IT8BenchmarkError.invalidManifest("\(key) must be an object")
        }
        return child
    }

    static func exactKeys(
        _ object: [String: Any],
        required: Set<String>,
        optional: Set<String>,
        field: String
    ) throws {
        let keys = Set(object.keys)
        let missing = required.subtracting(keys).sorted()
        let unknown = keys.subtracting(required.union(optional)).sorted()
        guard missing.isEmpty else {
            throw IT8BenchmarkError.invalidManifest(
                "\(field) is missing keys: \(missing.joined(separator: ", "))"
            )
        }
        guard unknown.isEmpty else {
            throw IT8BenchmarkError.invalidManifest(
                "\(field) contains unknown keys: \(unknown.joined(separator: ", "))"
            )
        }
    }
}
