import Foundation
import simd

extension ScannerTargetGrade {
    // MARK: 시그니처 3D LUT

    static let cubeDimension = 64

    private static let cubeCacheLock = NSLock()
    private nonisolated(unsafe) static var cubeCache: [Signature: Data] = [:]

    static func cubeData(for sig: Signature) -> Data {
        cubeCacheLock.lock()
        if let cached = cubeCache[sig] {
            cubeCacheLock.unlock()
            return cached
        }
        cubeCacheLock.unlock()
        let data = makeCubeData(signature: sig, dimension: cubeDimension)
        cubeCacheLock.lock()
        // 노출 앵커(exposureAnchored)가 장면별로 양자화된 톤 변형을 만들므로 한도를 여유 있게
        // 잡는다(변형 수는 0.004 양자화로 유한).
        if cubeCache.count >= 32 { cubeCache.removeAll(keepingCapacity: true) }
        cubeCache[sig] = data
        cubeCacheLock.unlock()
        return data
    }

    private struct PreparedSignature {
        var toneXs: [Double]
        var tone: [Double]
        var neutralBins: [NeutralBin]
        var hueAnchors: [HueAnchor]
        var chromaBands: [ChromaBand]
    }

    private static func preparedSignature(_ sig: Signature) -> PreparedSignature {
        // 톤 커브: knot 입력 위치(네거티브 = 실측 consensus, 포지티브 = 실측 중점) → 실기 출력값.
        // 끝점 (0,0)/(1,1) 고정(순흑/순백 보존), knot 별 이동량 ±0.25 클램프 + 단조 강제 —
        // 폭주 방지.
        var xs: [Double] = [0.0]
        var ys: [Double] = [0.0]
        for (index, anchorX) in sig.toneXs.enumerated() where index < sig.tone.count {
            let x = clamp(anchorX, 0.002, 0.998)
            xs.append(x)
            ys.append(clamp(sig.tone[index], max(x - 0.25, 0.002), min(x + 0.25, 0.998)))
        }
        // (참고) "조기 순백" knot 로 실기 화이트 클립을 재현하는 시도는 금지 — xs 는 재앵커
        // 상대 도메인이라 실제 렌더 명부(sRGB 0.87~0.98)와 대응하지 않아, knot 위치 근사가
        // 명부를 통째로 순백에 얹는 화이트홀을 만든다(QA 실측으로 두 번 확인된 실패).
        xs.append(1.0)
        ys.append(1.0)
        for i in 1..<xs.count - 1 where xs[i] <= xs[i - 1] {
            xs[i] = xs[i - 1] + 1e-4
        }
        for i in 1..<ys.count - 1 where ys[i] <= ys[i - 1] {
            ys[i] = ys[i - 1] + 1e-4
        }
        return PreparedSignature(
            toneXs: xs,
            tone: ys,
            neutralBins: sig.neutralBins.sorted { $0.luma < $1.luma },
            hueAnchors: sig.hueAnchors.sorted { $0.hueDegrees < $1.hueDegrees },
            chromaBands: sig.chromaBands.sorted { $0.luma < $1.luma }
        )
    }

    /// 상대 시그니처의 수학적 반대편. 실제 NORITSU/FUJI pair는 tone delta·neutral drift·
    /// hue rotation이 부호 반대이고, hue/band gain이 역수이므로 같은 lattice에서 양쪽의
    /// gamut 여유를 함께 계산할 수 있다.
    private static func reciprocal(_ sig: PreparedSignature) -> PreparedSignature {
        PreparedSignature(
            toneXs: sig.toneXs,
            tone: zip(sig.toneXs, sig.tone).map { x, y in x - (y - x) },
            neutralBins: sig.neutralBins.map { NeutralBin(luma: $0.luma, a: -$0.a, b: -$0.b) },
            hueAnchors: sig.hueAnchors.map {
                HueAnchor(
                    hueDegrees: $0.hueDegrees,
                    chromaGain: $0.chromaGain.isFinite && $0.chromaGain > 1e-9
                        ? 1.0 / $0.chromaGain : 1.0,
                    rotateDegrees: -$0.rotateDegrees
                )
            },
            chromaBands: sig.chromaBands.map {
                ChromaBand(
                    luma: $0.luma,
                    gain: $0.gain.isFinite && $0.gain > 1e-9 ? 1.0 / $0.gain : 1.0
                )
            }
        )
    }

    private static func transformedSRGB(
        input: SIMD3<Double>,
        inputLuma: Double,
        inputLab: (l: Double, a: Double, b: Double),
        signature sig: PreparedSignature
    ) -> SIMD3<Double> {
        let mappedLuma = relativeToneValue(at: inputLuma, xs: sig.toneXs, ys: sig.tone)
        let toneChanged = abs(mappedLuma - inputLuma) > 1e-12
        guard toneChanged || !sig.neutralBins.isEmpty
                || !sig.hueAnchors.isEmpty || !sig.chromaBands.isEmpty else { return input }

        var labL = inputLab.l
        var labA = inputLab.a
        var labB = inputLab.b
        if toneChanged {
            let inputNeutralL = srgbToLab(r: inputLuma, g: inputLuma, b: inputLuma).l
            let mappedNeutralL = srgbToLab(r: mappedLuma, g: mappedLuma, b: mappedLuma).l
            // 여기서 L*를 자르면 한 방향만 endpoint에 붙어 reciprocal 정보가 사라진다.
            // extended 후보를 그대로 두고 아래 공통 gamut scale에서 양쪽을 함께 줄인다.
            labL += mappedNeutralL - inputNeutralL
        }
        if !sig.hueAnchors.isEmpty || !sig.chromaBands.isEmpty {
            let chroma = (labA * labA + labB * labB).squareRoot()
            if chroma > 1e-6 {
                let hue = atan2(labB, labA)
                let (gain, rotate) = hueResponse(
                    at: hue * 180.0 / .pi,
                    anchors: sig.hueAnchors
                )
                let colorTaper = smoothstep(0.02, 0.10, inputLuma)
                    * (1.0 - smoothstep(0.90, 0.98, inputLuma))
                let measuredBandGain = chromaBandGain(at: inputLuma, bands: sig.chromaBands)
                let bandGain = exp(log(max(measuredBandGain, 1e-9)) * colorTaper)
                let measuredHueGain = sig.hueAnchors.isEmpty ? 1.0
                    : clamp(gain, hueChromaGainRange.lowerBound, hueChromaGainRange.upperBound)
                let hueGain = exp(log(max(measuredHueGain, 1e-9)) * colorTaper)
                let taperedRotation = clamp(rotate, -hueRotateLimit, hueRotateLimit) * colorTaper
                let newHue = hue + taperedRotation * .pi / 180.0
                let newChroma = chroma * clamp(hueGain * bandGain, 0.50, 2.0)
                labA = newChroma * cos(newHue)
                labB = newChroma * sin(newHue)
            }
        }
        if !sig.neutralBins.isEmpty {
            let taper = smoothstep(0.03, 0.10, inputLuma)
                * (1.0 - smoothstep(0.90, 0.97, inputLuma))
            // 중립축 드리프트는 "중립"에만 적용해야 한다: 입력 채도가 높을수록 0 으로 taper 한다.
            // 그래야 그레이 온도(예: FUJI 쿨 그레이)와 유채색 hue 개성(예: FUJI 골든 스킨)이
            // 서로 상쇄되지 않고 hue 앵커/chroma 대역이 유채색을 독립적으로 지배한다.
            let neutralChromaGate = 1.0 - smoothstep(8.0, 28.0, (inputLab.a * inputLab.a + inputLab.b * inputLab.b).squareRoot())
            let drift = neutralDrift(at: inputLuma, bins: sig.neutralBins)
            // 암부 웜캐스트 제거(픽셀 luma 기준): 좋은 스캔의 암부는 중립이어야 한다. 저 luma 에서
            // 웜(빨강 a*>0 / 노랑 b*>0) 드리프트를 0 에 수렴시키고, 쿨(파랑 b*<0)은 유지한다 —
            // FUJI 의 문서화된 특성이 "파란 그림자"이므로 블루 보존, 암부의 빨강/노랑만 제거한다.
            // 하이라이트는 warmGate=1 이라 레드 특성이 그대로 유지된다.
            let warmGate = smoothstep(0.22, 0.52, inputLuma)
            var driftA = clamp(drift.a, -4.0, 4.0)
            var driftB = clamp(drift.b, -4.0, 4.0)
            if driftA > 0 { driftA *= warmGate }
            if driftB > 0 { driftB *= warmGate }
            labA += driftA * taper * neutralChromaGate
            labB += driftB * taper * neutralChromaGate
        }
        let output = labToExtendedSRGB(l: labL, a: labA, b: labB)
        return SIMD3(output.r, output.g, output.b)
    }

    /// 같은 lattice 입력에서 정방향과 reciprocal 후보가 모두 sRGB unit gamut에 들어오는
    /// 최대 공통 배율. 후보 순서를 바꿔도 같은 값이며 한쪽만 hard-clamp되는 비대칭을 막는다.
    static func sharedRelativeGamutScale(
        input: SIMD3<Double>,
        candidate: SIMD3<Double>,
        reciprocalCandidate: SIMD3<Double>
    ) -> Double {
        guard input.x.isFinite, input.y.isFinite, input.z.isFinite,
              candidate.x.isFinite, candidate.y.isFinite, candidate.z.isFinite,
              reciprocalCandidate.x.isFinite,
              reciprocalCandidate.y.isFinite,
              reciprocalCandidate.z.isFinite else { return 0.0 }
        var scale = 1.0
        for output in [candidate, reciprocalCandidate] {
            for channel in 0..<3 {
                let delta = output[channel] - input[channel]
                if delta > 0 {
                    scale = min(scale, (1.0 - input[channel]) / delta)
                } else if delta < 0 {
                    scale = min(scale, (0.0 - input[channel]) / delta)
                }
            }
        }
        return clamp(scale, 0.0, 1.0)
    }

    static func makeCubeData(signature sig: Signature, dimension dim: Int) -> Data {
        let prepared = preparedSignature(sig)
        let reciprocal = reciprocal(prepared)

        var cube = [Float](repeating: 0, count: dim * dim * dim * 4)
        for bi in 0..<dim {
            let bInput = Double(bi) / Double(dim - 1)
            for gi in 0..<dim {
                let gInput = Double(gi) / Double(dim - 1)
                for ri in 0..<dim {
                    let rInput = Double(ri) / Double(dim - 1)
                    let input = SIMD3(rInput, gInput, bInput)
                    let inputLuma = 0.2126 * rInput + 0.7152 * gInput + 0.0722 * bInput
                    let inputLab = srgbToLab(r: rInput, g: gInput, b: bInput)
                    let candidate = transformedSRGB(
                        input: input,
                        inputLuma: inputLuma,
                        inputLab: inputLab,
                        signature: prepared
                    )
                    let reciprocalCandidate = transformedSRGB(
                        input: input,
                        inputLuma: inputLuma,
                        inputLab: inputLab,
                        signature: reciprocal
                    )
                    let scale = sharedRelativeGamutScale(
                        input: input,
                        candidate: candidate,
                        reciprocalCandidate: reciprocalCandidate
                    )
                    let output = input + (candidate - input) * scale
                    let offset = ((bi * dim + gi) * dim + ri) * 4
                    // 공통 scale이 unit gamut을 보장한다. clamp는 Float 반올림 오차 방어뿐이다.
                    cube[offset] = Float(clamp(output.x, 0.0, 1.0))
                    cube[offset + 1] = Float(clamp(output.y, 0.0, 1.0))
                    cube[offset + 2] = Float(clamp(output.z, 0.0, 1.0))
                    cube[offset + 3] = 1
                }
            }
        }
        return Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size)
    }

    /// 공통 입력 knot에 대한 상대 tone delta를 선형 보간한다. 양쪽 시그니처의 delta가
    /// 반대이면 모든 입력 지점에서 공통 baseline 주위 편차도 정확히 반대가 된다.
    static func relativeToneValue(at value: Double, xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, let firstX = xs.first, let lastX = xs.last,
              let firstY = ys.first, let lastY = ys.last else { return value }
        if value <= firstX { return firstY }
        if value >= lastX { return lastY }
        for index in 1..<xs.count where value <= xs[index] {
            let loX = xs[index - 1]
            let hiX = xs[index]
            let fraction = (value - loX) / max(hiX - loX, 1e-9)
            let loDelta = ys[index - 1] - loX
            let hiDelta = ys[index] - hiX
            return clamp(
                value + loDelta + (hiDelta - loDelta) * fraction,
                0.0,
                1.0
            )
        }
        return lastY
    }

    /// 대역 채도 배율을 luma 위치에서는 선형, gain에서는 log-domain으로 보간한다.
    /// 범위 밖은 가장 가까운 대역 값을 유지하고 끝점 taper가 별도로 1.0으로 되돌린다.
    static func chromaBandGain(at luma: Double, bands: [ChromaBand]) -> Double {
        guard let first = bands.first, let last = bands.last else { return 1.0 }
        if luma <= first.luma { return first.gain }
        if luma >= last.luma { return last.gain }
        for i in 1..<bands.count where luma <= bands[i].luma {
            let lo = bands[i - 1], hi = bands[i]
            let f = (luma - lo.luma) / max(hi.luma - lo.luma, 1e-6)
            return exp(log(max(lo.gain, 1e-9))
                + (log(max(hi.gain, 1e-9)) - log(max(lo.gain, 1e-9))) * f)
        }
        return last.gain
    }

    /// 중립축 드리프트를 luma bin 앵커 사이 선형 보간. 범위 밖은 가장 가까운 bin 값 유지
    /// (끝점 테이퍼가 별도로 0 으로 되돌린다).
    static func neutralDrift(at luma: Double, bins: [NeutralBin]) -> (a: Double, b: Double) {
        guard let first = bins.first, let last = bins.last else { return (0, 0) }
        if luma <= first.luma { return (first.a, first.b) }
        if luma >= last.luma { return (last.a, last.b) }
        for i in 1..<bins.count where luma <= bins[i].luma {
            let lo = bins[i - 1], hi = bins[i]
            let f = (luma - lo.luma) / max(hi.luma - lo.luma, 1e-6)
            return (lo.a + (hi.a - lo.a) * f, lo.b + (hi.b - lo.b) * f)
        }
        return (last.a, last.b)
    }

    /// hue 앵커 사이를 원형 보간한다. gain은 역수 대칭을 위한 log-domain, 회전은 각도
    /// 차이의 선형 보간이다.
    static func hueResponse(at hueDegrees: Double, anchors: [HueAnchor]) -> (gain: Double, rotate: Double) {
        guard !anchors.isEmpty else { return (1.0, 0.0) }
        if anchors.count == 1 { return (anchors[0].chromaGain, anchors[0].rotateDegrees) }
        let hue = ((hueDegrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        // 원형: 앞뒤 앵커를 wrap 포함으로 찾는다.
        var previous = anchors[anchors.count - 1]
        var previousHue = previous.hueDegrees - 360.0
        for anchor in anchors {
            if hue <= anchor.hueDegrees {
                let f = (hue - previousHue) / max(anchor.hueDegrees - previousHue, 1e-6)
                return (
                    exp(log(max(previous.chromaGain, 1e-9))
                        + (log(max(anchor.chromaGain, 1e-9))
                            - log(max(previous.chromaGain, 1e-9))) * f),
                    previous.rotateDegrees + (anchor.rotateDegrees - previous.rotateDegrees) * f
                )
            }
            previous = anchor
            previousHue = anchor.hueDegrees
        }
        // wrap: 마지막 앵커 → 첫 앵커(+360).
        let first = anchors[0]
        let f = (hue - previousHue) / max(first.hueDegrees + 360.0 - previousHue, 1e-6)
        return (
            exp(log(max(previous.chromaGain, 1e-9))
                + (log(max(first.chromaGain, 1e-9))
                    - log(max(previous.chromaGain, 1e-9))) * f),
            previous.rotateDegrees + (first.rotateDegrees - previous.rotateDegrees) * f
        )
    }
}
