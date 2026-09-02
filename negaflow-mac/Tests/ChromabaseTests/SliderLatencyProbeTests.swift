import XCTest
import CoreImage
import CoreGraphics
import Metal
import CoreVideo
@testable import Chromabase

/// 슬라이더 드래그 한 틱(현상 1회)의 실제 비용을 단계별로 재는 임시 계측.
/// NEGAFLOW_SLIDER_PROBE=1 일 때만 돈다.
final class SliderLatencyProbeTests: XCTestCase {
    private let width = 2816
    private let height = 1877

    func testSliderTickCostBreakdown() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NEGAFLOW_SLIDER_PROBE"] == "1",
            "Set NEGAFLOW_SLIDER_PROBE=1 to run the slider latency probe."
        )

        // 앱의 인터랙티브 입력과 동일한 형태: RGBA16 linear CGImage 백킹 CIImage.
        let input = try makeNegativeInput(width: width, height: height)
        let engine = ChromabaseEngine()
        let base = try XCTUnwrap(
            engine.estimateFilmBase(in: input, mode: .auto, filmType: .colorNegative)
        )

        let queue = try XCTUnwrap(MTLCreateSystemDefaultDevice()?.makeCommandQueue())
        let context = CIContext(mtlCommandQueue: queue, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

        func displayRender(_ image: CIImage) {
            let mapped = DisplayGamutMap.apply(to: image)
            _ = context.createCGImage(
                OutputDither.apply(to: mapped),
                from: mapped.extent,
                format: .RGBA8,
                colorSpace: srgb
            )
        }

        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main

        // 워밍업(커널 컴파일/텍스처 업로드 제외).
        for _ in 0..<3 {
            displayRender(engine.developScannerPreview(
                image: input, base: base, params: params, maxDimension: CGFloat(width)
            ))
        }

        for target in [DevelopTarget.main, .sp3000] {
            params.developTarget = target
            var full: [TimeInterval] = []
            for step in 1...12 {
                params.exposure = Double(step) * 0.02
                full.append(timed {
                    displayRender(engine.developScannerPreview(
                        image: input, base: base, params: params, maxDimension: CGFloat(width)
                    ))
                })
            }
            report("total \(target.displayName)", full)

            // 같은 조건에서 장면 측정을 재사용했을 때(= 실제 슬라이더 드래그 경로).
            var reuse = DevelopSceneMeasurements()
            _ = engine.developScannerPreview(
                image: input, base: base, params: params,
                maxDimension: CGFloat(width), measurements: &reuse
            )
            var cached: [TimeInterval] = []
            for step in 1...12 {
                params.exposure = Double(step) * 0.02
                cached.append(timed {
                    displayRender(engine.developScannerPreview(
                        image: input, base: base, params: params,
                        maxDimension: CGFloat(width), measurements: &reuse
                    ))
                })
            }
            report("total \(target.displayName) (measured once)", cached)
        }

        // 아직 캐시하지 않는 경로: EXPIRED(RescueGrade)와 자동 레벨/중립화 토글.
        for (name, mutate) in [
            ("EXPIRED", { (p: inout DevelopParameters) in p.developTarget = .rescue }),
            ("autoLevels", { (p: inout DevelopParameters) in p.autoLevels = true }),
            ("autoNeutral", { (p: inout DevelopParameters) in p.autoNeutralBalance = true }),
        ] {
            var variant = DevelopParameters()
            variant.filmType = .colorNegative
            variant.developTarget = .main
            mutate(&variant)
            var reuse = DevelopSceneMeasurements()
            _ = engine.developScannerPreview(
                image: input, base: base, params: variant,
                maxDimension: CGFloat(width), measurements: &reuse
            )
            var times: [TimeInterval] = []
            for step in 1...10 {
                variant.exposure = Double(step) * 0.02
                times.append(timed {
                    displayRender(engine.developScannerPreview(
                        image: input, base: base, params: variant,
                        maxDimension: CGFloat(width), measurements: &reuse
                    ))
                })
            }
            report("tick \(name) (measured once)", times)
        }

        params.developTarget = .main
        params.exposure = 0

        // 분해 1 — 반전 통계 readback(입력 raw + base 에만 의존, 슬라이더 무관).
        var statsTimes: [TimeInterval] = []
        for _ in 0..<12 {
            statsTimes.append(timed {
                _ = NegativeInversion.sampleStats(input, base: base, filmType: .colorNegative)
            })
        }
        report("sampleStats", statsTimes)

        // 분해 2 — 장면 평균 채도 readback(반전 결과에 의존, 역시 슬라이더 무관).
        let stats = try XCTUnwrap(NegativeInversion.sampleStats(input, base: base, filmType: .colorNegative))
        let inverted = NegativeInversion.applyDensityEncoding(
            to: input, stats: stats, response: NegativeInversion.response(for: .colorNegative)
        )
        var satTimes: [TimeInterval] = []
        for _ in 0..<12 {
            satTimes.append(timed {
                _ = NegativeInversion.sceneMeanSaturation(inverted)
            })
        }
        report("sceneMeanSaturation", satTimes)

        // 분해 3 — CIImage 그래프 구성만(지연 평가, GPU 실행 없음).
        var buildTimes: [TimeInterval] = []
        for step in 1...12 {
            params.exposure = Double(step) * 0.02
            buildTimes.append(timed {
                _ = engine.developScannerPreview(
                    image: input, base: base, params: params, maxDimension: CGFloat(width)
                )
            })
        }
        report("graph build (incl. readbacks)", buildTimes)

        // 분해 4 — 최종 createCGImage 만(그래프는 고정, GPU 실행 + readback).
        params.exposure = 0.1
        let developed = engine.developScannerPreview(
            image: input, base: base, params: params, maxDimension: CGFloat(width)
        )
        var renderTimes: [TimeInterval] = []
        for _ in 0..<12 {
            renderTimes.append(timed { displayRender(developed) })
        }
        report("final createCGImage", renderTimes)

        // 분해 5 — 입력을 그대로 내보내는 최소 렌더(파이프라인 없는 하한).
        var passthroughTimes: [TimeInterval] = []
        for _ in 0..<12 {
            passthroughTimes.append(timed {
                _ = context.createCGImage(input, from: input.extent, format: .RGBA8, colorSpace: srgb)
            })
        }
        report("passthrough createCGImage", passthroughTimes)

        // 분해 6 — sampleStats 안에서 GPU readback 과 CPU 후처리가 각각 얼마인지.
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let extent = input.extent.integral
        let targetW = max(64, min(320, Int(extent.width)))
        let statScale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * statScale))
        let scaled = input.transformed(by: CGAffineTransform(scaleX: statScale, y: statScale))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        var readbackTimes: [TimeInterval] = []
        for _ in 0..<12 {
            readbackTimes.append(timed {
                SamplingContextPool.context(workingColorSpace: linear).render(
                    scaled,
                    toBitmap: &bitmap,
                    rowBytes: targetW * 4 * MemoryLayout<Float>.size,
                    bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                    format: .RGBAf,
                    colorSpace: linear
                )
            })
        }
        report("  └ stats readback (\(targetW)px)", readbackTimes)

        // 분해 7 — 통계를 미리 알고 있을 때(캐시 적중 가정)의 한 틱 비용.
        var cachedTimes: [TimeInterval] = []
        for step in 1...12 {
            params.exposure = Double(step) * 0.02
            cachedTimes.append(timed {
                let encoded = NegativeInversion.applyDensityEncoding(
                    to: input, stats: stats, response: NegativeInversion.response(for: .colorNegative)
                )
                // 채도 부스트 양도 캐시된 값이라 가정하고, 반전 이후 단계만 잇는다.
                var tail = params
                tail.filmType = .colorNegative
                tail.imageTransform = .identity
                var img = ColorModel.apply(to: encoded, params: tail)
                img = ToneMapper.applyExposure(to: img, stops: tail.exposure)
                img = ToneMapper.applyToneCurves(to: img, params: tail)
                img = engine.applyPostPipeline(to: img, params: tail, extent: encoded.extent)
                displayRender(img)
            })
        }
        report("tick with cached stats", cachedTimes)

        // 분해 8 — 프록시 긴 변별 한 틱(측정 재사용). throttle 을 얼마로 잡아야 하는지의 근거.
        for dimension in [1024, 1536, 2048, 2816, 3600] as [Int] {
            let scaled = scaledInput(input, longEdge: dimension, context: context)
            var reuse = DevelopSceneMeasurements()
            var warm = params
            warm.developTarget = .main
            _ = engine.developScannerPreview(
                image: scaled, base: base, params: warm,
                maxDimension: CGFloat(dimension), measurements: &reuse
            )
            var times: [TimeInterval] = []
            for step in 1...10 {
                warm.exposure = Double(step) * 0.02
                times.append(timed {
                    displayRender(engine.developScannerPreview(
                        image: scaled, base: base, params: warm,
                        maxDimension: CGFloat(dimension), measurements: &reuse
                    ))
                })
            }
            report("tick @\(dimension)px", times)
        }

        // 분해 9 — 표시 경로를 CPU 로 내리지 않고 GPU 표면에만 그렸을 때(readback 제거 상한).
        let surfaceAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            surfaceAttributes as CFDictionary, &pixelBuffer
        )
        if let buffer = pixelBuffer {
            var reuse = DevelopSceneMeasurements()
            var warm = params
            warm.developTarget = .main
            _ = engine.developScannerPreview(
                image: input, base: base, params: warm,
                maxDimension: CGFloat(width), measurements: &reuse
            )
            var times: [TimeInterval] = []
            for step in 1...12 {
                warm.exposure = Double(step) * 0.02
                times.append(timed {
                    let developed = engine.developScannerPreview(
                        image: input, base: base, params: warm,
                        maxDimension: CGFloat(width), measurements: &reuse
                    )
                    let mapped = DisplayGamutMap.apply(to: developed)
                    context.render(
                        OutputDither.apply(to: mapped),
                        to: buffer,
                        bounds: mapped.extent,
                        colorSpace: srgb
                    )
                })
            }
            report("tick → GPU surface (no CGImage)", times)
        }
    }

    private func scaledInput(_ image: CIImage, longEdge: Int, context: CIContext) -> CIImage {
        let extent = image.extent.integral
        let scale = CGFloat(longEdge) / max(extent.width, extent.height)
        guard scale < 1 else { return image }
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropped = scaled.cropped(to: scaled.extent.integral)
        guard let cg = context.createCGImage(
            cropped,
            from: cropped.extent,
            format: .RGBA16,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        ) else { return cropped }
        return CIImage(cgImage: cg, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
    }

    // MARK: helpers

    private func report(_ label: String, _ values: [TimeInterval]) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let mean = values.reduce(0, +) / Double(values.count)
        print(String(
            format: "[probe] %-30@ median %6.1f ms   mean %6.1f ms   min %6.1f ms   max %6.1f ms",
            label as NSString, median * 1000, mean * 1000, sorted.first! * 1000, sorted.last! * 1000
        ))
    }

    private func timed(_ body: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        return CFAbsoluteTimeGetCurrent() - start
    }

    /// 오렌지 마스크 위에 장면 밀도가 실린 합성 네거티브(실사진 미사용).
    private func makeNegativeInput(width: Int, height: Int) throws -> CIImage {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y) / Double(height - 1)
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                // 장면 밝기(0.05~0.95)를 네거티브 밀도로 뒤집고 오렌지 베이스 투과율을 곱한다.
                let scene = 0.05 + 0.9 * (0.5 + 0.5 * sin(fx * 7.1) * cos(fy * 5.3))
                let density = 1.0 - scene
                let r = 0.86 * (0.12 + 0.88 * density)
                let g = 0.68 * (0.10 + 0.90 * density * 0.94)
                let b = 0.50 * (0.08 + 0.92 * density * 0.88)
                let i = (y * width + x) * 4
                pixels[i] = UInt16(max(0, min(65_535, r * 65_535)))
                pixels[i + 1] = UInt16(max(0, min(65_535, g * 65_535)))
                pixels[i + 2] = UInt16(max(0, min(65_535, b * 65_535)))
                pixels[i + 3] = UInt16.max
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!
        let cg = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            space: linear,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return CIImage(cgImage: cg, options: [.colorSpace: linear])
    }
}
