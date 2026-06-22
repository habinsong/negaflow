import Foundation
import CoreImage

// MARK: - NegativeInversion (plan §8.6)
//
// 검증된 방법론: darktable `negadoctor` (Kodak Cineon 밀도 모델) + RawTherapee
// 채널별 거듭제곱 모델. 두 도구 모두 같은 핵심을 공유한다.
//
//   1. 스캔 투과광 → 광학 밀도:  D = -log10(transmission / Dmin)
//                              = log10(Dmin / transmission)   (per channel)
//      Dmin = 미노광 필름 베이스(오렌지 마스크) 투과율. 이걸 빼는 것이 마스크 제거다.
//   2. 채널별 밀도 정규화:  Dn = D / Dmax_c
//      → 채널마다 다른 감마(기울기)를 독립 정규화하므로 오렌지/붉은 캐스트가 사라진다.
//        (= 자동 화이트밸런스. 단순 1/base 나눗셈이 캐스트를 남기는 이유가 이것.)
//   3. positive 공간 채널별 black/white point (auto-levels).
//   4. 페이퍼 감마(대비).
//
// 단순 `1 - RGB` 반전은 금지(plan §8.6): 밀도는 로그이고 베이스는 오렌지이며
// 채널마다 기울기가 달라, 선형 반전은 붉은 끼·잘못된 대비·채도를 만든다.
//
// 변환이 채널별로 완전히 분리(R_out=f_R(R_in) 등)되므로 CIColorCube로 정확히 구현된다.
// 채도를 인위적으로 부풀리지 않는다 — 색은 밀도 반전에서 자연스럽게 나온다.
public enum NegativeInversion {
    /// 채널별 밀도 통계. 모두 raw 투과광(0...1 linear) 좌표계 기준.
    struct ChannelStats {
        var dmin: SIMD3<Double>       // 필름 베이스 투과율(가장 밝은 = 가장 얇은 밀도)
        var dmaxNorm: SIMD3<Double>   // 채널별 최대 밀도(정규화 분모) — 채널별 WB의 핵심
        var blackInput: SIMD3<Double> // positive black point에 대응하는 입력 투과율(밝은 쪽)
    }

    /// density-based 네거티브 반전을 적용한 CIImage를 반환한다.
    public static func apply(to image: CIImage, base: FilmBase) -> CIImage {
        let stats = sampleStats(image, base: base)
            ?? fallbackStats(base: base)
        return applyCube(to: image, stats: stats)
    }

    // MARK: 채널별 통계 샘플링

    static func sampleStats(_ image: CIImage, base: FilmBase) -> ChannelStats? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }

        // 작은 축소본을 linear 영역에서 렌더해 채널별 히스토그램을 만든다.
        let targetW = max(64, min(320, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))

        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf,
            colorSpace: linear
        )

        // 검은 프레임 경계(필름 홀더)를 제외하기 위해 내부 6% 인셋만 사용한다.
        let insetX = max(1, Int(Double(targetW) * 0.06))
        let insetY = max(1, Int(Double(targetH) * 0.06))
        var red: [Double] = [], green: [Double] = [], blue: [Double] = []
        red.reserveCapacity(targetW * targetH)
        for y in insetY..<max(insetY + 1, targetH - insetY) {
            for x in insetX..<max(insetX + 1, targetW - insetX) {
                let i = (y * targetW + x) * 4
                red.append(Double(bitmap[i]))
                green.append(Double(bitmap[i + 1]))
                blue.append(Double(bitmap[i + 2]))
            }
        }
        guard red.count >= 64 else { return nil }
        red.sort(); green.sort(); blue.sort()

        func pct(_ s: [Double], _ f: Double) -> Double {
            let idx = max(0, min(s.count - 1, Int(Double(s.count - 1) * f)))
            return s[idx]
        }

        // Dmin = 가장 밝은 투과율(p99.8). 베이스 추정값이 더 밝으면 그쪽을 신뢰.
        let sampledDmin = SIMD3(pct(red, 0.998), pct(green, 0.998), pct(blue, 0.998))
        let dmin = SIMD3(
            max(sampledDmin.x, base.rgb.x * 0.5),
            max(sampledDmin.y, base.rgb.y * 0.5),
            max(sampledDmin.z, base.rgb.z * 0.5)
        )
        // 가장 밀도 높은 장면(밝은 피사체) = p0.2 투과율.
        let densest = SIMD3(
            max(pct(red, 0.002), 1e-5),
            max(pct(green, 0.002), 1e-5),
            max(pct(blue, 0.002), 1e-5)
        )
        // 채널별 최대 밀도(정규화 분모).
        let dmaxNorm = SIMD3(
            max(0.4, log10(dmin.x / densest.x)),
            max(0.4, log10(dmin.y / densest.y)),
            max(0.4, log10(dmin.z / densest.z))
        )
        let paperBlackInput = SIMD3(pct(red, 0.90), pct(green, 0.90), pct(blue, 0.90)) * 0.97
        let stats = ChannelStats(dmin: dmin, dmaxNorm: dmaxNorm, blackInput: paperBlackInput)
        if ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil {
            FileHandle.standardError.write(Data((
                "[nega] dmin=\(fmt(dmin)) dmaxNorm=\(fmt(dmaxNorm)) blackIn=\(fmt(paperBlackInput))\n"
            ).utf8))
        }
        return stats
    }

    private static func fmt(_ v: SIMD3<Double>) -> String {
        String(format: "(%.4f,%.4f,%.4f)", v.x, v.y, v.z)
    }

    static func fallbackStats(base: FilmBase) -> ChannelStats {
        let dmin = SIMD3(max(base.rgb.x, 0.05), max(base.rgb.y, 0.05), max(base.rgb.z, 0.05))
        return ChannelStats(
            dmin: dmin,
            dmaxNorm: SIMD3(repeating: 2.2),
            blackInput: dmin
        )
    }

    // MARK: 채널별 변환 → CIColorCube

    /// 정규화 밀도(0...1)를 positive 값으로 매핑하는 한 채널 변환.
    /// shadow toe → 감마 → Reinhard 하이라이트 숄더.
    private static func positiveValue(transmission t: Double,
                                      dmin: Double, dmaxNorm: Double,
                                      blackDn: Double,
                                      gamma: Double, knee: Double) -> Double {
        let clamped = max(t, 1e-5)
        if clamped >= dmin * 0.985 {
            return 0
        }
        let density = log10(dmin / clamped)        // 베이스→0, 밀도 높은 장면→큼
        let dn = max(0.0, density / dmaxNorm)       // 채널별 정규화(오렌지 캐스트 제거)
        let toeEnd = min(max(blackDn, 0.006), 0.18)
        let toeOutput = 0.0013
        let lifted: Double
        if dn <= toeEnd {
            lifted = toeOutput * pow(dn / toeEnd, 2.45)
        } else {
            let normalized = (dn - toeEnd) / max(1.0 - toeEnd, 1e-3)
            lifted = toeOutput + (1.0 - toeOutput) * min(max(normalized, 0.0), 1.0)
        }
        var v = pow(lifted, gamma)
        // Reinhard 하이라이트 숄더: knee 위를 부드럽게 압축해 1.0으로 수렴(디테일 보존).
        if v > knee {
            v = knee + (v - knee) / (1.0 + (v - knee) / max(1.0 - knee, 1e-3))
        }
        return min(max(v, 0.0), 1.0)
    }

    static func applyCube(to image: CIImage, stats: ChannelStats) -> CIImage {
        let dimension = 96
        // 페이퍼 감마(대비). 1/1.3 ≈ 0.77 → 미드톤 적정. negadoctor 페이퍼 그레이드 근사.
        let gamma = 1.0 / 1.3
        let knee = 0.70   // 하이라이트 롤오프 시작점

        // 입력 black point를 정규화 밀도 좌표로 변환.
        func dnOf(_ t: Double, _ c: Int) -> Double {
            max(0.0, log10(stats.dmin[c] / max(t, 1e-5)) / stats.dmaxNorm[c])
        }
        let blackDn = SIMD3(dnOf(stats.blackInput.x, 0), dnOf(stats.blackInput.y, 1), dnOf(stats.blackInput.z, 2))

        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        // 채널별로 분리되므로 1D 곡선을 미리 계산해 둔다.
        func curve(_ c: Int) -> [Double] {
            (0..<dimension).map { i in
                let t = Double(i) / Double(dimension - 1)
                return positiveValue(transmission: t,
                                     dmin: stats.dmin[c], dmaxNorm: stats.dmaxNorm[c],
                                     blackDn: blackDn[c],
                                     gamma: gamma, knee: knee)
            }
        }
        let rCurve = curve(0), gCurve = curve(1), bCurve = curve(2)

        for b in 0..<dimension {
            let bv = Float(bCurve[b])
            for g in 0..<dimension {
                let gv = Float(gCurve[g])
                for r in 0..<dimension {
                    let offset = ((b * dimension + g) * dimension + r) * 4
                    cube[offset]     = Float(rCurve[r])
                    cube[offset + 1] = gv
                    cube[offset + 2] = bv
                    cube[offset + 3] = 1
                }
            }
        }

        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ]).cropped(to: image.extent)
    }
}
