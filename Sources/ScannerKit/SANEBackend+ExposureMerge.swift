import Foundation
import Chromabase
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    static func averageMultiSampleScans(sampleURLs: [URL], outputURL: URL) throws {
        let images = sampleURLs.compactMap { Chromabase.ImageLoader.loadScannerTIFF($0) }
        guard images.count == sampleURLs.count, !images.isEmpty else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let bitmap = try averageMultiSampleBitmap(images)
        try writeRGB16TIFF(bitmap.pixels, width: bitmap.width, height: bitmap.height, to: outputURL)
    }

    static func mergeHardwareExposureScans(sampleURLs: [URL], exposureTimes: [Int], outputURL: URL) throws {
        let images = sampleURLs.compactMap { Chromabase.ImageLoader.loadScannerTIFF($0) }
        guard images.count == sampleURLs.count, !images.isEmpty else {
            throw ScannerError(.ioFailure, "hardware exposure TIFF 로드 실패")
        }
        let bitmap = try mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        try writeRGB16TIFF(bitmap.pixels, width: bitmap.width, height: bitmap.height, to: outputURL)
    }

    static func averageMultiSampleScans(_ images: [CIImage]) -> CIImage {
        guard let first = images.first else {
            return CIImage.empty()
        }
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB),
              let averaged = try? alignedAverageRGBAf(images, colorSpace: linear) else {
            return first
        }
        return CIImage(
            bitmapData: Data(bytes: averaged.pixels, count: averaged.pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: averaged.width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: averaged.width, height: averaged.height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    static func averageMultiSampleBitmap(_ images: [CIImage]) throws -> (pixels: [UInt16], width: Int, height: Int) {
        guard !images.isEmpty,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let averaged = try alignedAverageRGBAf(images, colorSpace: linear)
        var pixels = [UInt16](repeating: 0, count: averaged.width * averaged.height * 3)
        var out = 0
        for index in stride(from: 0, to: averaged.pixels.count, by: 4) {
            pixels[out] = UInt16(min(max(averaged.pixels[index], 0), 1) * 65535)
            pixels[out + 1] = UInt16(min(max(averaged.pixels[index + 1], 0), 1) * 65535)
            pixels[out + 2] = UInt16(min(max(averaged.pixels[index + 2], 0), 1) * 65535)
            out += 3
        }
        return (pixels, averaged.width, averaged.height)
    }

    static func mergeHardwareExposureBitmap(
        _ images: [CIImage],
        exposureTimes: [Int]
    ) throws -> (pixels: [UInt16], width: Int, height: Int) {
        guard images.count == exposureTimes.count, !images.isEmpty,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw ScannerError(.ioFailure, "hardware exposure 입력 오류")
        }
        guard let referenceExposure = referenceExposureTime(from: exposureTimes),
              referenceExposure > 0 else {
            throw ScannerError(.ioFailure, "hardware exposure 기준값 오류")
        }
        let normalized = try alignedExposureNormalizedRGBAf(
            images,
            exposureTimes: exposureTimes,
            referenceExposure: referenceExposure,
            colorSpace: linear
        )
        var pixels = [UInt16](repeating: 0, count: normalized.width * normalized.height * 3)
        var out = 0
        for index in stride(from: 0, to: normalized.pixels.count, by: 4) {
            pixels[out] = UInt16(min(max(normalized.pixels[index], 0), 1) * 65535)
            pixels[out + 1] = UInt16(min(max(normalized.pixels[index + 1], 0), 1) * 65535)
            pixels[out + 2] = UInt16(min(max(normalized.pixels[index + 2], 0), 1) * 65535)
            out += 3
        }
        return (pixels, normalized.width, normalized.height)
    }

    private static func alignedAverageRGBAf(
        _ images: [CIImage],
        colorSpace linear: CGColorSpace
    ) throws -> (pixels: [Float], width: Int, height: Int) {
        guard let first = images.first else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let extent = first.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 크기 오류")
        }

        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        let rendered = images.map { image in
            renderRGBAf(image.cropped(to: extent), width: width, height: height, context: context, colorSpace: linear)
        }
        guard let reference = rendered.first else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let offsets = rendered.map { estimateIntegerOffset(reference: reference, sample: $0, width: width, height: height) }
        var accumulator = [Float](repeating: 0, count: width * height * 4)
        var counts = [Float](repeating: 0, count: width * height)
        for (sample, offset) in zip(rendered, offsets) {
            accumulateAligned(sample, offset: offset, width: width, height: height, into: &accumulator, counts: &counts)
        }
        for pixel in 0..<(width * height) {
            let count = max(counts[pixel], 1)
            let offset = pixel * 4
            accumulator[offset] = min(max(accumulator[offset] / count, 0), 1)
            accumulator[offset + 1] = min(max(accumulator[offset + 1] / count, 0), 1)
            accumulator[offset + 2] = min(max(accumulator[offset + 2] / count, 0), 1)
            accumulator[offset + 3] = 1
        }
        return (accumulator, width, height)
    }

    private static func alignedExposureNormalizedRGBAf(
        _ images: [CIImage],
        exposureTimes: [Int],
        referenceExposure: Int,
        colorSpace linear: CGColorSpace
    ) throws -> (pixels: [Float], width: Int, height: Int) {
        let first = images[0]
        let extent = first.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else {
            throw ScannerError(.ioFailure, "hardware exposure TIFF 크기 오류")
        }

        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        let rendered = images.map { image in
            renderRGBAf(image.cropped(to: extent), width: width, height: height, context: context, colorSpace: linear)
        }
        let normalized = zip(rendered, exposureTimes).map { sample, exposureTime in
            normalizeExposure(sample, exposureTime: exposureTime, referenceExposure: referenceExposure)
        }
        let referenceIndex = exposureTimes.enumerated()
            .min { abs($0.element - referenceExposure) < abs($1.element - referenceExposure) }?
            .offset ?? 0
        let reference = normalized[referenceIndex]
        let offsets = normalized.map { estimateIntegerOffset(reference: reference, sample: $0, width: width, height: height) }
        var merged = [Float](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let destination = (y * width + x) * 4
                for channel in 0..<3 {
                    merged[destination + channel] = mergedHardwareExposureValue(
                        x: x,
                        y: y,
                        channel: channel,
                        rendered: rendered,
                        normalized: normalized,
                        exposureTimes: exposureTimes,
                        referenceExposure: referenceExposure,
                        referenceIndex: referenceIndex,
                        offsets: offsets,
                        width: width,
                        height: height
                    )
                }
                merged[destination + 3] = 1
            }
        }
        return (merged, width, height)
    }

    private static func normalizeExposure(_ pixels: [Float], exposureTime: Int, referenceExposure: Int) -> [Float] {
        let scale = Float(referenceExposure) / Float(exposureTime)
        var out = pixels
        for index in stride(from: 0, to: out.count, by: 4) {
            out[index] *= scale
            out[index + 1] *= scale
            out[index + 2] *= scale
            out[index + 3] = 1
        }
        return out
    }

    private static func mergedHardwareExposureValue(
        x: Int,
        y: Int,
        channel: Int,
        rendered: [[Float]],
        normalized: [[Float]],
        exposureTimes: [Int],
        referenceExposure: Int,
        referenceIndex: Int,
        offsets: [(x: Int, y: Int)],
        width: Int,
        height: Int
    ) -> Float {
        let referenceSource = alignedSourceIndex(
            x: x,
            y: y,
            channel: channel,
            offset: offsets[referenceIndex],
            width: width,
            height: height
        )
        let fallback = (y * width + x) * 4 + channel
        let baselineIndex = referenceSource ?? min(fallback, normalized[referenceIndex].count - 1)
        let baselineRaw = rendered[referenceIndex][baselineIndex]

        var value = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 == referenceExposure }
        ) ?? normalized[referenceIndex][baselineIndex]
        if let short = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 < referenceExposure }
        ) {
            let amount = smoothstep(edge0: 0.82, edge1: 0.97, x: baselineRaw)
            value = mix(value, short, amount)
        }
        if let long = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 > referenceExposure }
        ) {
            let amount = (1 - smoothstep(edge0: 0.010, edge1: 0.045, x: baselineRaw)) * 0.48
            value = mix(value, long, amount)
        }
        return min(max(value, 0), 1)
    }

    static func referenceExposureTime(from exposureTimes: [Int]) -> Int? {
        let unique = Array(Set(exposureTimes)).sorted()
        guard !unique.isEmpty else { return nil }
        return unique[unique.count / 2]
    }

    private static func alternateExposureValue(
        x: Int,
        y: Int,
        channel: Int,
        rendered: [[Float]],
        normalized: [[Float]],
        exposureTimes: [Int],
        offsets: [(x: Int, y: Int)],
        width: Int,
        height: Int,
        matching predicate: (Int) -> Bool
    ) -> Float? {
        var weightedSum: Float = 0
        var weightSum: Float = 0
        for index in rendered.indices where predicate(exposureTimes[index]) {
            guard let source = alignedSourceIndex(
                x: x,
                y: y,
                channel: channel,
                offset: offsets[index],
                width: width,
                height: height
            ) else {
                continue
            }
            let rawValue = rendered[index][source]
            let weight = exposureTrustWeight(rawValue)
            weightedSum += normalized[index][source] * weight
            weightSum += weight
        }
        guard weightSum > 0.0001 else { return nil }
        return weightedSum / weightSum
    }

    private static func alignedSourceIndex(
        x: Int,
        y: Int,
        channel: Int,
        offset: (x: Int, y: Int),
        width: Int,
        height: Int
    ) -> Int? {
        let sx = x + offset.x
        let sy = y + offset.y
        guard sx >= 0, sx < width, sy >= 0, sy < height else { return nil }
        return (sy * width + sx) * 4 + channel
    }

    private static func exposureTrustWeight(_ rawValue: Float) -> Float {
        if rawValue >= 0.985 { return 0.02 }
        if rawValue >= 0.90 {
            return max(0.05, (0.985 - rawValue) / 0.085)
        }
        if rawValue <= 0.006 { return 0.02 }
        if rawValue <= 0.035 {
            return max(0.05, (rawValue - 0.006) / 0.029)
        }
        return 1
    }

    private static func mix(_ a: Float, _ b: Float, _ amount: Float) -> Float {
        let t = min(max(amount, 0), 1)
        return a + (b - a) * t
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge0 != edge1 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func renderRGBAf(
        _ image: CIImage,
        width: Int,
        height: Int,
        context: CIContext,
        colorSpace linear: CGColorSpace
    ) -> [Float] {
        var buffer = [Float](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { rawBuffer in
            context.render(
                image,
                toBitmap: rawBuffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }
        return buffer
    }

    /// 패스 간 정렬 오프셋 추정. 다운샘플 피라미드로 거칠게 찾고 풀해상도에서 미세보정한다.
    /// 필름 이송(세로/feed 축) 흔들림이 3600dpi에서 수십 픽셀에 달하므로 세로(dy)를 넓게 탐색한다.
    private static func estimateIntegerOffset(
        reference: [Float],
        sample: [Float],
        width: Int,
        height: Int
    ) -> (x: Int, y: Int) {
        // 다운샘플 배율은 이미지 크기에 적응(작은 이미지/테스트에선 1px 정렬도 가능하게).
        let factor = max(1, min(8, min(width, height) / 96))
        let (ref, dw, dh) = downsampledLuma(reference, width: width, height: height, factor: factor)
        let (smp, _, _) = downsampledLuma(sample, width: width, height: height, factor: factor)
        guard dw > 6, dh > 6 else { return (0, 0) }
        // 텍스처 가드는 휘도 레벨에 상대적으로 둔다 — 네거티브 raw는 절대 휘도가 낮아(ADC 일부만 사용)
        // 고정 임계면 구조가 충분한데도 항상 스킵돼 정렬이 (0,0)으로 빠진다. 평균 대비 비율로 판정.
        let refMean = max(ref.reduce(0, +) / Float(max(ref.count, 1)), 1e-6)
        guard downsampledTexture(ref, width: dw, height: dh) > Double(refMean) * 0.008 else { return (0, 0) }

        let baseline = downsampledError(ref, smp, width: dw, height: dh, dx: 0, dy: 0)
        var best = (x: 0, y: 0)
        var bestError = baseline
        let yRange = max(1, min(96 / factor, (dh - 6) / 2))   // 세로/이송 축 — 넓게(이미지 범위 내로 클램프)
        let xRange = max(1, min(16 / factor, (dw - 6) / 2))   // 가로/크로스피드 — 좁게
        for dy in -yRange...yRange {
            for dx in -xRange...xRange {
                let error = downsampledError(ref, smp, width: dw, height: dh, dx: dx, dy: dy)
                if error < bestError { bestError = error; best = (dx, dy) }
            }
        }
        guard bestError < baseline * 0.85 else { return (0, 0) }

        // 풀해상도 미세보정: 다운샘플 최적점(×factor) 주변 ±factor(세로)·±2(가로).
        var fx = best.x * factor
        var fy = best.y * factor
        var fineError = fullResLumaError(reference, sample, width: width, height: height, dx: fx, dy: fy)
        for dy in (fy - factor)...(fy + factor) {
            for dx in (fx - 2)...(fx + 2) {
                let error = fullResLumaError(reference, sample, width: width, height: height, dx: dx, dy: dy)
                if error < fineError { fineError = error; fx = dx; fy = dy }
            }
        }
        return (fx, fy)
    }

    /// factor×factor 블록 평균으로 휘도를 다운샘플(노이즈 억제 + 빠른 탐색).
    private static func downsampledLuma(_ pixels: [Float], width: Int, height: Int, factor: Int) -> (luma: [Float], width: Int, height: Int) {
        let dw = width / factor, dh = height / factor
        guard dw > 0, dh > 0 else { return ([], 0, 0) }
        var out = [Float](repeating: 0, count: dw * dh)
        let inv = 1.0 / Float(factor * factor)
        for by in 0..<dh {
            let y0 = by * factor
            for bx in 0..<dw {
                let x0 = bx * factor
                var sum: Float = 0
                for yy in y0..<(y0 + factor) {
                    let row = yy * width
                    for xx in x0..<(x0 + factor) {
                        let i = (row + xx) * 4
                        sum += pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722
                    }
                }
                out[by * dw + bx] = sum * inv
            }
        }
        // 3x3 블러로 미세 패턴/노이즈를 죽인다 → 정렬이 거친 구조(장면)에만 반응(노이즈는 정렬하지 않음).
        return (boxBlur3(out, width: dw, height: dh), dw, dh)
    }

    /// 분리형 3x3 박스 블러.
    private static func boxBlur3(_ buf: [Float], width: Int, height: Int) -> [Float] {
        guard width >= 3, height >= 3 else { return buf }
        let third: Float = 1.0 / 3.0
        var tmp = buf
        for y in 0..<height {
            let r = y * width
            for x in 1..<(width - 1) {
                tmp[r + x] = (buf[r + x - 1] + buf[r + x] + buf[r + x + 1]) * third
            }
        }
        var out = tmp
        for y in 1..<(height - 1) {
            for x in 0..<width {
                out[y * width + x] = (tmp[(y - 1) * width + x] + tmp[y * width + x] + tmp[(y + 1) * width + x]) * third
            }
        }
        return out
    }

    private static func downsampledError(_ ref: [Float], _ smp: [Float], width: Int, height: Int, dx: Int, dy: Int) -> Double {
        let inset = 2 + max(abs(dx), abs(dy))
        guard width > 2 * inset, height > 2 * inset else { return .greatestFiniteMagnitude }
        var total = 0.0
        var count = 0
        for y in inset..<(height - inset) {
            let rRow = y * width, sRow = (y + dy) * width
            for x in inset..<(width - inset) {
                total += abs(Double(ref[rRow + x] - smp[sRow + x + dx]))
                count += 1
            }
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private static func downsampledTexture(_ luma: [Float], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                total += abs(Double(luma[row + x] - luma[row + x + 1]))
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private static func fullResLumaError(_ reference: [Float], _ sample: [Float], width: Int, height: Int, dx: Int, dy: Int) -> Double {
        let step = max(1, min(width, height) / 256)
        let inset = 4 + max(abs(dx), abs(dy))
        guard width > 2 * inset, height > 2 * inset else { return .greatestFiniteMagnitude }
        var total = 0.0
        var count = 0
        var y = inset
        while y < height - inset {
            let sy = y + dy
            var x = inset
            while x < width - inset {
                let r = (y * width + x) * 4
                let s = (sy * width + x + dx) * 4
                let rl = reference[r] * 0.2126 + reference[r + 1] * 0.7152 + reference[r + 2] * 0.0722
                let sl = sample[s] * 0.2126 + sample[s + 1] * 0.7152 + sample[s + 2] * 0.0722
                total += abs(Double(rl - sl))
                count += 1
                x += step
            }
            y += step
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private static func accumulateAligned(
        _ sample: [Float],
        offset: (x: Int, y: Int),
        width: Int,
        height: Int,
        into accumulator: inout [Float],
        counts: inout [Float]
    ) {
        for y in 0..<height {
            let sy = y + offset.y
            guard sy >= 0, sy < height else { continue }
            for x in 0..<width {
                let sx = x + offset.x
                guard sx >= 0, sx < width else { continue }
                let source = (sy * width + sx) * 4
                let destination = (y * width + x) * 4
                accumulator[destination] += sample[source]
                accumulator[destination + 1] += sample[source + 1]
                accumulator[destination + 2] += sample[source + 2]
                counts[y * width + x] += 1
            }
        }
    }

    private static func writeLinearTIFF(_ image: CIImage, to url: URL) throws {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBAh, colorSpace: linear) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 이미지 생성 실패")
        }
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 출력 생성 실패")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 출력 저장 실패")
        }
    }

    private static func writeRGB16TIFF(_ pixels: [UInt16], width: Int, height: Int, to url: URL) throws {
        let bigEndianPixels = pixels.map(\.bigEndian)
        var data = Data(count: bigEndianPixels.count * MemoryLayout<UInt16>.size)
        data.withUnsafeMutableBytes { destination in
            bigEndianPixels.withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 48,
                bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw ScannerError(.ioFailure, "multi-sample RGB16 이미지 생성 실패")
        }
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 출력 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 출력 저장 실패")
        }
    }
}
