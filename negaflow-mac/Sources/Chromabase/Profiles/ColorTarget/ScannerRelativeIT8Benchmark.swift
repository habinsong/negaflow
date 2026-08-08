import CoreGraphics
import CoreImage
import CryptoKit
import Foundation

/// Runs a fixed synthetic color-negative through MAIN, NORITSU, and FUJI twice.
///
/// The scanner outputs are a regression of the bundled roll-label aggregate relative style.
/// They are not a characterization of an HS-1800 or SP-3000 device, scanner unit, operator
/// settings, or a paired physical target.
public enum ScannerRelativeIT8Benchmark {
    public static let benchmarkKind = "NORITSU/FUJI roll-label aggregate relative style regression"

    private static let rows = 12
    private static let columns = 22
    private static let patchSize = 4
    // IT8.7/1 및 IT8.7/2의 중립 density scale은 A16...L16 세로 열이다.
    private static let neutralColumn = 15
    private static let filmBase = SIMD3<Double>(0.84, 0.55, 0.34)

    public static func evaluate(
        referenceBytes: Data,
        expectedReferenceSHA256: String
    ) throws -> ScannerRelativeIT8BenchmarkReport {
        try validateSHA256(expectedReferenceSHA256)
        let actualReferenceSHA256 = sha256(referenceBytes)
        guard actualReferenceSHA256 == expectedReferenceSHA256 else {
            throw ScannerRelativeIT8BenchmarkError.referenceSHA256Mismatch(
                expected: expectedReferenceSHA256,
                actual: actualReferenceSHA256
            )
        }

        let document: IT8ReferenceDocument
        do {
            document = try IT8ReferenceParser.parse(referenceBytes)
        } catch {
            throw ScannerRelativeIT8BenchmarkError.referenceParseFailed(String(describing: error))
        }
        let references = try indexedReference(document)
        let fixture = try makeSyntheticNegative(references: references)
        guard let profileBundle = ScannerProfileRegistry.loadValidatedBundle() else {
            throw ScannerRelativeIT8BenchmarkError.scannerProfileBundleUnavailable
        }
        let matchedPairs = ScannerTargetGrade.matchedProfilePairs(
            scanner: "NORITSU",
            kind: "color nega",
            profiles: profileBundle.profiles
        )
        guard !matchedPairs.isEmpty,
              ScannerTargetGrade.scannerSignature(
                  scanner: "NORITSU", profiles: profileBundle.profiles
              ) != nil,
              ScannerTargetGrade.scannerSignature(
                  scanner: "SP-3000", profiles: profileBundle.profiles
              ) != nil else {
            throw ScannerRelativeIT8BenchmarkError.scannerRelativePairUnavailable
        }
        let pairIdentities = matchedPairs.map { pair in
            ScannerRelativeIT8BenchmarkReport.RelativeProfilePairIdentity(
                kind: pair.mine.kind,
                filmKey: pair.mine.filmKey,
                noritsuProfileID: pair.mine.id,
                fujiProfileID: pair.other.id,
                noritsuImageCount: pair.mine.imageCount,
                fujiImageCount: pair.other.imageCount
            )
        }

        guard let extendedLinearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw ScannerRelativeIT8BenchmarkError.renderingUnavailable("extendedLinearSRGB")
        }
        let context = CIContext(options: [
            .workingColorSpace: extendedLinearSRGB,
            .outputColorSpace: extendedLinearSRGB,
            .workingFormat: CIFormat.RGBAf,
            .cacheIntermediates: false,
        ])
        let engine = ChromabaseEngine()
        let main = renderTwice(
            target: .main,
            fixture: fixture.image,
            engine: engine,
            context: context,
            colorSpace: extendedLinearSRGB
        )
        let noritsu = renderTwice(
            target: .noritsu,
            fixture: fixture.image,
            engine: engine,
            context: context,
            colorSpace: extendedLinearSRGB
        )
        let fuji = renderTwice(
            target: .sp3000,
            fixture: fixture.image,
            engine: engine,
            context: context,
            colorSpace: extendedLinearSRGB
        )

        var patches: [ScannerRelativeIT8BenchmarkReport.Patch] = []
        patches.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                let id = patchID(row: row, column: column)
                guard let reference = references[id] else {
                    throw ScannerRelativeIT8BenchmarkError.missingReferencePatch(id)
                }
                let input = fixture.patches[row * columns + column]
                let mainMeasurement = measurement(
                    pixels: main.first,
                    row: row,
                    column: column,
                    reference: reference.lab
                )
                let noritsuMeasurement = measurement(
                    pixels: noritsu.first,
                    row: row,
                    column: column,
                    reference: reference.lab
                )
                let fujiMeasurement = measurement(
                    pixels: fuji.first,
                    row: row,
                    column: column,
                    reference: reference.lab
                )
                let noritsuFromMain = deltaE(mainMeasurement.labD50, noritsuMeasurement.labD50)
                let fujiFromMain = deltaE(mainMeasurement.labD50, fujiMeasurement.labD50)
                let noritsuFuji = deltaE(noritsuMeasurement.labD50, fujiMeasurement.labD50)
                let inputDelta = ColorTargetColorimetry.deltaE2000(input.lab, reference.lab)
                let valid = inputDelta.isFinite
                    && mainMeasurement.isValid
                    && noritsuMeasurement.isValid
                    && fujiMeasurement.isValid
                    && noritsuFromMain?.isFinite == true
                    && fujiFromMain?.isFinite == true
                    && noritsuFuji?.isFinite == true

                patches.append(ScannerRelativeIT8BenchmarkReport.Patch(
                    id: id,
                    row: row,
                    column: column,
                    referenceLabD50: reference.lab,
                    inputLinearRGB: .init(input.linearRGB),
                    inputLabD50: input.lab,
                    inputDeltaE00FromReference: inputDelta,
                    syntheticNegativeTransmissionRGB: .init(input.transmission),
                    inputWorkingRangeFlags: workingRangeFlags(input.linearRGB),
                    main: mainMeasurement,
                    noritsu: noritsuMeasurement,
                    fuji: fujiMeasurement,
                    noritsuDeltaE00FromMain: noritsuFromMain,
                    fujiDeltaE00FromMain: fujiFromMain,
                    noritsuFujiDeltaE00: noritsuFuji,
                    valid: valid
                ))
            }
        }

        let summary = makeSummary(
            patches: patches,
            repeatability: .init(
                mainBitExact: main.bitExact,
                noritsuBitExact: noritsu.bitExact,
                fujiBitExact: fuji.bitExact
            )
        )
        return ScannerRelativeIT8BenchmarkReport(
            benchmarkKind: benchmarkKind,
            reference: .init(
                sha256: actualReferenceSHA256,
                patchCount: references.count,
                interpretedIlluminant: "D50",
                interpretedObserver: "CIE1931_2deg"
            ),
            syntheticModel: .init(
                modelName: "bounded fixed color-negative print-response forward model",
                filmBaseLinearRGB: .init(filmBase),
                densityEncodingVersion: NegativeInversion.genericDensityEncodingVersion,
                densityEncodingRange: NegativeInversion.colorResponse.normalRange,
                rows: rows,
                columns: columns,
                patchSize: patchSize
            ),
            profileBundle: profileBundle.identity,
            relativeProfilePairs: pairIdentities,
            patches: patches,
            summary: summary
        )
    }
}

private extension ScannerRelativeIT8Benchmark {
    typealias Report = ScannerRelativeIT8BenchmarkReport

    struct SyntheticPatch {
        let linearRGB: SIMD3<Double>
        let lab: ColorTargetLab
        let transmission: SIMD3<Double>
    }

    struct SyntheticFixture {
        let image: CIImage
        let patches: [SyntheticPatch]
    }

    struct RenderPair {
        let first: [Float]
        let bitExact: Bool
    }

    struct PatchSample {
        let mean: SIMD3<Double>?
        let flags: [Report.WorkingRangeFlag]
    }

    static func validateSHA256(_ value: String) throws {
        let prefix = "sha256:"
        guard value.hasPrefix(prefix), value.count == prefix.count + 64 else {
            throw ScannerRelativeIT8BenchmarkError.invalidExpectedReferenceSHA256(value)
        }
        let digest = value.dropFirst(prefix.count)
        guard digest.allSatisfy({
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }) else {
            throw ScannerRelativeIT8BenchmarkError.invalidExpectedReferenceSHA256(value)
        }
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
    }

    static func indexedReference(
        _ document: IT8ReferenceDocument
    ) throws -> [String: IT8ReferencePatch] {
        let expectedCount = rows * columns
        guard document.patches.count == expectedCount else {
            throw ScannerRelativeIT8BenchmarkError.invalidReferencePatchCount(
                expected: expectedCount,
                actual: document.patches.count
            )
        }
        let required = Set((0..<rows).flatMap { row in
            (0..<columns).map { patchID(row: row, column: $0) }
        })
        var result: [String: IT8ReferencePatch] = [:]
        result.reserveCapacity(expectedCount)
        for patch in document.patches {
            let id = patch.normalizedID
            guard required.contains(id) else {
                throw ScannerRelativeIT8BenchmarkError.unexpectedReferencePatch(id)
            }
            guard patch.lab.isFinite else {
                throw ScannerRelativeIT8BenchmarkError.nonFiniteReferencePatch(id)
            }
            result[id] = patch
        }
        for id in required where result[id] == nil {
            throw ScannerRelativeIT8BenchmarkError.missingReferencePatch(id)
        }
        return result
    }

    static func makeSyntheticNegative(
        references: [String: IT8ReferencePatch]
    ) throws -> SyntheticFixture {
        let width = columns * patchSize
        let height = rows * patchSize
        var bitmap = [Float](repeating: 1, count: width * height * 4)
        var patches: [SyntheticPatch] = []
        patches.reserveCapacity(rows * columns)

        for row in 0..<rows {
            for column in 0..<columns {
                let id = patchID(row: row, column: column)
                guard let reference = references[id] else {
                    throw ScannerRelativeIT8BenchmarkError.missingReferencePatch(id)
                }
                let linear = ColorTargetColorimetry.labD50ToLinearSRGB(reference.lab)
                let transmission = SIMD3<Double>(
                    syntheticTransmission(forLinear: linear.x, base: filmBase.x),
                    syntheticTransmission(forLinear: linear.y, base: filmBase.y),
                    syntheticTransmission(forLinear: linear.z, base: filmBase.z)
                )
                let inputLab = ColorTargetColorimetry.linearSRGBToLabD50(linear)
                guard linear.isFinite, transmission.isFinite, inputLab.isFinite else {
                    throw ScannerRelativeIT8BenchmarkError.nonFiniteSyntheticInput(id)
                }
                patches.append(SyntheticPatch(
                    linearRGB: linear,
                    lab: inputLab,
                    transmission: transmission
                ))

                for localY in 0..<patchSize {
                    let y = row * patchSize + localY
                    for localX in 0..<patchSize {
                        let x = column * patchSize + localX
                        let offset = (y * width + x) * 4
                        bitmap[offset] = Float(transmission.x)
                        bitmap[offset + 1] = Float(transmission.y)
                        bitmap[offset + 2] = Float(transmission.z)
                    }
                }
            }
        }

        guard let extendedLinearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw ScannerRelativeIT8BenchmarkError.renderingUnavailable("extendedLinearSRGB")
        }
        let data = bitmap.withUnsafeBytes { Data($0) }
        return SyntheticFixture(
            image: CIImage(
                bitmapData: data,
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: extendedLinearSRGB
            ),
            patches: patches
        )
    }

    static func renderTwice(
        target: DevelopTarget,
        fixture: CIImage,
        engine: ChromabaseEngine,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> RenderPair {
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = target
        params.baseEstimationMode = .manual
        params.manualBaseRGB = filmBase
        let base = FilmBase(rgb: filmBase, source: .manual)

        let firstImage = engine.developScanner(image: fixture, base: base, params: params)
        let first = render(firstImage, context: context, colorSpace: colorSpace)
        let secondImage = engine.developScanner(image: fixture, base: base, params: params)
        let second = render(secondImage, context: context, colorSpace: colorSpace)
        return RenderPair(first: first, bitExact: bitExact(first, second))
    }

    static func render(
        _ image: CIImage,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> [Float] {
        let width = columns * patchSize
        let height = rows * patchSize
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
        return pixels
    }

    static func bitExact(_ first: [Float], _ second: [Float]) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { pair in
            pair.0.bitPattern == pair.1.bitPattern
        }
    }

    static func measurement(
        pixels: [Float],
        row: Int,
        column: Int,
        reference: ColorTargetLab
    ) -> Report.RenderMeasurement {
        let sample = patchSample(pixels: pixels, row: row, column: column)
        guard let mean = sample.mean else {
            return Report.RenderMeasurement(
                linearRGB: nil,
                labD50: nil,
                deltaE00FromReference: nil,
                workingRangeFlags: sample.flags
            )
        }
        let lab = ColorTargetColorimetry.linearSRGBToLabD50(mean)
        let delta = ColorTargetColorimetry.deltaE2000(lab, reference)
        guard lab.isFinite, delta.isFinite else {
            var flags = sample.flags
            if !flags.contains(.containsNonFiniteChannel) {
                flags.append(.containsNonFiniteChannel)
            }
            return Report.RenderMeasurement(
                linearRGB: .init(mean),
                labD50: nil,
                deltaE00FromReference: nil,
                workingRangeFlags: flags
            )
        }
        return Report.RenderMeasurement(
            linearRGB: .init(mean),
            labD50: lab,
            deltaE00FromReference: delta,
            workingRangeFlags: sample.flags
        )
    }

    static func patchSample(pixels: [Float], row: Int, column: Int) -> PatchSample {
        let width = columns * patchSize
        var sum = SIMD3<Double>(repeating: 0)
        var finiteCount = 0
        var hasZero = false
        var hasOne = false
        var hasBelowZero = false
        var hasAboveOne = false
        var hasNonFinite = false

        for localY in 0..<patchSize {
            let y = row * patchSize + localY
            for localX in 0..<patchSize {
                let x = column * patchSize + localX
                let offset = (y * width + x) * 4
                let value = SIMD3<Double>(
                    Double(pixels[offset]),
                    Double(pixels[offset + 1]),
                    Double(pixels[offset + 2])
                )
                for channel in [value.x, value.y, value.z] {
                    if !channel.isFinite {
                        hasNonFinite = true
                    } else if channel < 0 {
                        hasBelowZero = true
                    } else if channel == 0 {
                        hasZero = true
                    } else if channel > 1 {
                        hasAboveOne = true
                    } else if channel == 1 {
                        hasOne = true
                    }
                }
                if value.isFinite {
                    sum += value
                    finiteCount += 1
                }
            }
        }

        var flags: [Report.WorkingRangeFlag] = []
        if hasZero { flags.append(.containsChannelAtZeroEndpoint) }
        if hasOne { flags.append(.containsChannelAtOneEndpoint) }
        if hasBelowZero { flags.append(.containsChannelBelowZero) }
        if hasAboveOne { flags.append(.containsChannelAboveOne) }
        if hasNonFinite { flags.append(.containsNonFiniteChannel) }
        let pixelCount = patchSize * patchSize
        return PatchSample(
            mean: finiteCount == pixelCount ? sum / Double(pixelCount) : nil,
            flags: flags
        )
    }

    static func workingRangeFlags(_ value: SIMD3<Double>) -> [Report.WorkingRangeFlag] {
        var hasZero = false
        var hasOne = false
        var hasBelowZero = false
        var hasAboveOne = false
        var hasNonFinite = false
        for channel in [value.x, value.y, value.z] {
            if !channel.isFinite {
                hasNonFinite = true
            } else if channel < 0 {
                hasBelowZero = true
            } else if channel == 0 {
                hasZero = true
            } else if channel > 1 {
                hasAboveOne = true
            } else if channel == 1 {
                hasOne = true
            }
        }
        var flags: [Report.WorkingRangeFlag] = []
        if hasZero { flags.append(.containsChannelAtZeroEndpoint) }
        if hasOne { flags.append(.containsChannelAtOneEndpoint) }
        if hasBelowZero { flags.append(.containsChannelBelowZero) }
        if hasAboveOne { flags.append(.containsChannelAboveOne) }
        if hasNonFinite { flags.append(.containsNonFiniteChannel) }
        return flags
    }

    static func deltaE(_ first: ColorTargetLab?, _ second: ColorTargetLab?) -> Double? {
        guard let first, let second else { return nil }
        let value = ColorTargetColorimetry.deltaE2000(first, second)
        return value.isFinite ? value : nil
    }

    static func makeSummary(
        patches: [Report.Patch],
        repeatability: Report.RepeatabilitySummary
    ) -> Report.Summary {
        let extended = patches.filter { isExtended($0.inputLinearRGB) }
        let unitCube = patches.filter { !isExtended($0.inputLinearRGB) }
        return Report.Summary(
            totalPatchCount: patches.count,
            validPatchCount: patches.filter(\.valid).count,
            nonFinitePatchCount: patches.count { patch in
                patch.main.workingRangeFlags.contains(.containsNonFiniteChannel)
                    || patch.noritsu.workingRangeFlags.contains(.containsNonFiniteChannel)
                    || patch.fuji.workingRangeFlags.contains(.containsNonFiniteChannel)
            },
            repeatability: repeatability,
            neutralTone: Report.NeutralToneSummary(
                columnID: String(neutralColumn + 1),
                main: neutralToneSummary(patches, measurement: \.main),
                noritsu: neutralToneSummary(patches, measurement: \.noritsu),
                fuji: neutralToneSummary(patches, measurement: \.fuji)
            ),
            extendedRange: Report.ExtendedRangeSummary(
                inputExcursionPatchCount: extended.count,
                mainExcursionDirectionPreservedPatchCount: extended.filter {
                    preservesExcursionDirection(input: $0.inputLinearRGB, output: $0.main.linearRGB)
                }.count,
                noritsuExcursionDirectionPreservedPatchCount: extended.filter {
                    preservesExcursionDirection(input: $0.inputLinearRGB, output: $0.noritsu.linearRGB)
                }.count,
                fujiExcursionDirectionPreservedPatchCount: extended.filter {
                    preservesExcursionDirection(input: $0.inputLinearRGB, output: $0.fuji.linearRGB)
                }.count,
                noritsuPatchMeanRGBEqualToMainPatchCount: extended.filter {
                    $0.noritsu.linearRGB != nil && $0.noritsu.linearRGB == $0.main.linearRGB
                }.count,
                fujiPatchMeanRGBEqualToMainPatchCount: extended.filter {
                    $0.fuji.linearRGB != nil && $0.fuji.linearRGB == $0.main.linearRGB
                }.count
            ),
            relativeDeltaE00: Report.RelativeDeltaSummary(
                noritsuFromMain: deltaDistribution(patches.compactMap(\.noritsuDeltaE00FromMain)),
                fujiFromMain: deltaDistribution(patches.compactMap(\.fujiDeltaE00FromMain)),
                noritsuFuji: deltaDistribution(patches.compactMap(\.noritsuFujiDeltaE00)),
                unitCubeInputPatchCount: unitCube.count,
                noritsuFromMainWithinUnitCube: deltaDistribution(
                    unitCube.compactMap(\.noritsuDeltaE00FromMain)
                ),
                fujiFromMainWithinUnitCube: deltaDistribution(
                    unitCube.compactMap(\.fujiDeltaE00FromMain)
                ),
                noritsuFujiWithinUnitCube: deltaDistribution(
                    unitCube.compactMap(\.noritsuFujiDeltaE00)
                )
            )
        )
    }

    static func deltaDistribution(_ source: [Double]) -> Report.DeltaDistribution {
        let values = source.filter(\.isFinite).sorted()
        return Report.DeltaDistribution(
            finitePatchCount: values.count,
            medianDeltaE00: percentile(values, fraction: 0.50),
            p95DeltaE00: percentile(values, fraction: 0.95),
            maximumDeltaE00: values.last
        )
    }

    static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let position = min(max(fraction, 0), 1) * Double(values.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return values[lower] }
        let weight = position - Double(lower)
        return values[lower] * (1 - weight) + values[upper] * weight
    }

    static func neutralToneSummary(
        _ patches: [Report.Patch],
        measurement: KeyPath<Report.Patch, Report.RenderMeasurement>
    ) -> Report.NeutralToneTargetSummary {
        let neutral = patches.filter { $0.column == neutralColumn }.sorted { $0.row < $1.row }
        var expectedCount = 0
        var comparedCount = 0
        var reversalCount = 0
        var plateauCount = 0
        var nonFiniteCount = 0

        for pair in zip(neutral, neutral.dropFirst()) {
            let referenceDifference = pair.1.referenceLabD50.l - pair.0.referenceLabD50.l
            guard referenceDifference != 0 else { continue }
            expectedCount += 1
            guard let first = pair.0[keyPath: measurement].labD50?.l,
                  let second = pair.1[keyPath: measurement].labD50?.l,
                  first.isFinite, second.isFinite else {
                nonFiniteCount += 1
                continue
            }
            comparedCount += 1
            let outputDifference = second - first
            if outputDifference == 0 {
                plateauCount += 1
            } else if referenceDifference * outputDifference < 0 {
                reversalCount += 1
            }
        }
        return Report.NeutralToneTargetSummary(
            expectedAdjacentPairCount: expectedCount,
            comparedAdjacentPairCount: comparedCount,
            reversedAdjacentPairCount: reversalCount,
            exactPlateauAdjacentPairCount: plateauCount,
            nonFiniteAdjacentPairCount: nonFiniteCount
        )
    }

    static func preservesExcursionDirection(input: Report.RGB, output: Report.RGB?) -> Bool {
        guard let output else { return false }
        return zip(input.channels, output.channels).allSatisfy { pair in
            if pair.0 < 0 { return pair.1 < 0 }
            if pair.0 > 1 { return pair.1 > 1 }
            return true
        }
    }

    static func isExtended(_ rgb: Report.RGB) -> Bool {
        rgb.channels.contains { $0 < 0 || $0 > 1 }
    }

    static func syntheticTransmission(forLinear value: Double, base: Double) -> Double {
        // 고정 인화 응답은 표시용 (baseToe, ceiling) 개구간 함수다. reference Lab의
        // extended-linear sRGB 값은 실제 필름 투과율로 역부호화할 수 없으므로 역함수가
        // 합성 입력에서 표현 가능한 범위로 클램프한다.
        let response = NegativeInversion.colorResponse
        let normalized = response.normalizedDensity(forLinearOutput: value)
        return base * pow(10.0, -normalized * response.normalRange)
    }

    static func patchID(row: Int, column: Int) -> String {
        String(UnicodeScalar(65 + row)!) + String(column + 1)
    }
}

private extension ScannerRelativeIT8BenchmarkReport.RGB {
    init(_ value: SIMD3<Double>) {
        self.init(r: value.x, g: value.y, b: value.z)
    }

    var channels: [Double] { [r, g, b] }
}

private extension ScannerRelativeIT8BenchmarkReport.RenderMeasurement {
    var isValid: Bool {
        linearRGB != nil
            && labD50 != nil
            && deltaE00FromReference?.isFinite == true
            && !workingRangeFlags.contains(.containsNonFiniteChannel)
    }
}

private extension SIMD3 where Scalar == Double {
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

private extension ColorTargetLab {
    var isFinite: Bool { l.isFinite && a.isFinite && b.isFinite }
}
