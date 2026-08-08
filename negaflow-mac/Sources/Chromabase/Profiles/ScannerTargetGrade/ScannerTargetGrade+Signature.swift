import Foundation

extension ScannerTargetGrade {
    // MARK: 실기 시그니처

    /// 실측 톤 시그니처 percentile 키.
    static let designPercentiles: [Double] = [0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99]
    static let toneKeys: [String] = ["p1", "p5", "p10", "p25", "p50", "p75", "p90", "p95", "p99"]

    /// 반전 렌더링의 미드 앵커(감마 도메인) = srgbEncode(0.18). 반전(NegativeInversion)이
    /// 적정 18% 회색을 linear 0.18 에 두는 photometric 설계(2026-07-17)와 일치해야 한다.
    /// 과거의 "percentile q ≈ 작업값 q"(p50 = linear 0.5 = sRGB 0.735) 앵커는 반전의 옛
    /// 로그-직결 렌더링을 전제한 것으로, 실기 실측 p50(sRGB 0.50~0.62)보다 0.6~1.2 스탑
    /// 밝아 모든 에뮬레이션 타겟의 과다 밝기 원인이었다.
    static let photometricMidTone = srgbEncode(NegativeInversion.midGrayLinear)

    /// 톤 knot 의 기본 입력 위치(감마 도메인). 항등 시그니처 구성(포지티브/모노 틴트 등
    /// toneXs == tone 사용처)의 기본값이며, 네거티브 시그니처는 scannerSignature 가 실측
    /// 기반 toneXs 를 명시적으로 채운다.
    static var designToneXs: [Double] { designPercentiles.map(srgbEncode) }

    struct NeutralBin: Equatable, Hashable {
        var luma: Double     // 감마 도메인 Rec.709 luma bin 중심
        var a: Double        // Lab a* 실측 드리프트(중립 픽셀 기준)
        var b: Double        // Lab b*
    }

    struct HueAnchor: Equatable, Hashable {
        var hueDegrees: Double      // Lab hue 앵커 각
        var chromaGain: Double
        var rotateDegrees: Double
    }

    /// luma 대역별 Lab chroma 배율 — 명시적으로 같은 source roll-label set을 가진 두
    /// 실기의 color.shadow/mid/high_chroma 비를 대칭 분배한 값이다.
    struct ChromaBand: Equatable, Hashable {
        var luma: Double     // 감마 도메인 luma 대역 중심(분석기 ZONE_BANDS 정합)
        var gain: Double
    }

    /// hue 시그니처 chromaGain 클램프. 컴파일러가 roll-label matched group에서
    /// **대칭 분배한 상대값**
    /// (실측: NOR×SP ≈ 1.0, 범위 0.55~1.82)이므로 자름 없이 수용해야 실기 색 캐릭터
    /// (NOR 레드/옐로 풍부, SP 틸 강조·레드 뮤트 — 랩 실사례 방향)가 살아난다. 과거
    /// 0.88..1.15 는 실측의 대부분을 잘라 캐릭터를 뭉갰다. 상·하한은 서로 역수여서
    /// 두 타겟의 대칭성을 보존하며, 오측정 폭주만 막는다.
    static let hueChromaGainRange = (1.0 / 1.85)...1.85
    static let hueRotateLimit = 8.0
    /// 대역별 채도 배율 클램프(대칭 분배 √비율, 역수 대칭 방어 상한).
    static let chromaBandGainRange = (1.0 / 1.60)...1.60

    struct Signature: Equatable, Hashable {
        var toneXs: [Double]            // 톤 knot 입력 위치(감마 도메인). 기본 = 설계 앵커 srgbEncode(q)
        var tone: [Double]              // knot 별 실기 출력 luma(감마 도메인)
        var neutralBins: [NeutralBin]
        var hueAnchors: [HueAnchor]
        /// 대역별 채도 배율(명시적 source roll 쌍 대칭 분배). 빈 배열 = 변조 없음.
        var chromaBands: [ChromaBand]

        init(
            toneXs: [Double]? = nil,
            tone: [Double],
            neutralBins: [NeutralBin],
            hueAnchors: [HueAnchor],
            chromaBands: [ChromaBand] = []
        ) {
            self.toneXs = toneXs ?? ScannerTargetGrade.designToneXs
            self.tone = tone
            self.neutralBins = neutralBins
            self.hueAnchors = hueAnchors
            self.chromaBands = chromaBands
        }
    }

    static func signature(of profile: ScannerProfile) -> Signature {
        let tone = toneKeys.enumerated().map { index, key in
            clamp(profile.tone[key]?.median ?? srgbEncode(designPercentiles[index]), 0.0, 1.0)
        }
        let neutralBins = (profile.neutralAxisBins ?? [])
            .filter { $0.coveragePct >= 0.02 }
            .map { NeutralBin(luma: $0.lumaCenter, a: $0.labA, b: $0.labB) }
        let hueAnchors = (profile.hueResponse ?? []).map {
            HueAnchor(
                hueDegrees: $0.labHueDegrees,
                chromaGain: clamp($0.chromaGain, hueChromaGainRange.lowerBound, hueChromaGainRange.upperBound),
                rotateDegrees: clamp($0.hueRotateDegrees, -hueRotateLimit, hueRotateLimit)
            )
        }
        return Signature(
            tone: tone,
            neutralBins: neutralBins,
            hueAnchors: hueAnchors
        )
    }

    /// 두 집계 프로파일이 같은 source roll **label 집합**에서 만들어졌는지 확인한다.
    /// 이 메타데이터에는 원본 frame ID/hash가 없으므로 같은 프레임 전체를 증명하지 않는다.
    /// filmKey나 이미지 수 유사성만으로는 roll-label pairing도 성립하지 않는다.
    static func hasMatchedRollLabelProvenance(_ lhs: ScannerProfile, _ rhs: ScannerProfile) -> Bool {
        guard lhs.kind == rhs.kind,
              lhs.filmKey == rhs.filmKey,
              let lhsRolls = sourceRollKeys(for: lhs),
              let rhsRolls = sourceRollKeys(for: rhs) else { return false }
        return lhsRolls == rhsRolls
    }

    private static func sourceRollKeys(for profile: ScannerProfile) -> Set<String>? {
        guard profile.rollCount > 0,
              profile.sourceProfiles.count == profile.rollCount,
              let scannerKey = normalizedProvenanceComponent(profile.scanner) else { return nil }
        let keys = profile.sourceProfiles.compactMap { source -> String? in
            let rawComponents = source
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: true)
            var components: [String] = []
            components.reserveCapacity(rawComponents.count)
            for component in rawComponents {
                guard let normalized = normalizedProvenanceComponent(String(component)) else {
                    return nil
                }
                components.append(normalized)
            }
            guard let scannerIndex = components.firstIndex(of: scannerKey),
                  scannerIndex + 2 < components.count else { return nil }
            return components[(scannerIndex + 1)...].joined(separator: "/")
        }
        guard keys.count == profile.sourceProfiles.count else { return nil }
        let unique = Set(keys)
        return unique.count == keys.count ? unique : nil
    }

    /// 프로파일 컴파일러와 바이트 단위로 같은 portable provenance 규칙이다.
    /// Unicode case-fold/locale 버전 차이를 피하기 위해 ASCII만 받고, 여섯 ASCII 공백을
    /// 양끝에서 제거한 뒤 A-Z만 a-z로 내린다. 비 ASCII는 pair 근거로 쓰지 않는다.
    private static func normalizedProvenanceComponent(_ value: String) -> String? {
        var bytes = Array(value.utf8)
        guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A, 0x0B, 0x0C]
        while bytes.first.map(whitespace.contains) == true { bytes.removeFirst() }
        while bytes.last.map(whitespace.contains) == true { bytes.removeLast() }
        for index in bytes.indices where (0x41...0x5A).contains(bytes[index]) {
            bytes[index] += 0x20
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    struct MatchedProfilePair {
        var mine: ScannerProfile
        var other: ScannerProfile
    }

    /// compiler의 hue pairing과 같은 관찰 수 허용 오차. roll label만 같고 실제 집계 범위가
    /// 크게 다른 두 corpus를 장치 차이로 오인하지 않기 위한 보수적 coverage guard다.
    static let pairedImageCountTolerance = 0.15

    static func hasComparableImageCoverage(_ lhs: ScannerProfile, _ rhs: ScannerProfile) -> Bool {
        guard lhs.imageCount > 0, rhs.imageCount > 0 else { return false }
        return Double(abs(lhs.imageCount - rhs.imageCount)) / Double(max(lhs.imageCount, rhs.imageCount))
            <= pairedImageCountTolerance
    }

    /// 같은 kind/filmKey/source roll-label set을 가지며 관찰 수가 ±15% 안인 프로파일을
    /// 결정적인 1:1 쌍으로 만든다.
    /// 현재 schema에는 frame ID/hash가 없으므로 이름 그대로 roll-label matched evidence다.
    static func matchedProfilePairs(
        scanner: String,
        kind: String,
        profiles: [ScannerProfile],
        filmKey: String? = nil
    ) -> [MatchedProfilePair] {
        guard let otherScanner = pairedScanner(of: scanner) else { return [] }
        let eligible = profiles.filter { profile in
            profile.validationStatus.allowsExplicitTargetUse
                && profile.kind == kind
                && (filmKey == nil || profile.filmKey == filmKey)
        }
        let mine = eligible.filter { $0.scanner == scanner }.sorted { $0.id < $1.id }
        let others = eligible.filter { $0.scanner == otherScanner }.sorted { $0.id < $1.id }
        var usedOtherIDs: Set<String> = []
        var pairs: [MatchedProfilePair] = []
        for profile in mine {
            guard let other = others.first(where: {
                !usedOtherIDs.contains($0.id)
                    && hasMatchedRollLabelProvenance(profile, $0)
                    && hasComparableImageCoverage(profile, $0)
            }) else { continue }
            usedOtherIDs.insert(other.id)
            pairs.append(MatchedProfilePair(mine: profile, other: other))
        }
        return pairs
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 0
            ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            : sorted[n / 2]
    }

    /// 여러 roll-label pair가 같은 방향을 보일 때만 상대 성분을 남긴다. 필름/장면에 따라
    /// 부호가 뒤집히면 장치 특성으로 분리할 근거가 없으므로 항등값(0)을 반환한다.
    static func consistentRelativeMedian(_ values: [Double], epsilon: Double = 1e-6) -> Double {
        let finite = values.filter(\.isFinite)
        let significant = finite.filter { abs($0) > epsilon }
        guard let first = significant.first else { return 0.0 }
        let positive = first > 0
        guard significant.allSatisfy({ ($0 > 0) == positive }) else { return 0.0 }
        return median(finite) ?? 0.0
    }

    static func binsByLuma(_ profile: ScannerProfile) -> [Int: (a: Double, b: Double)] {
        var result: [Int: (a: Double, b: Double)] = [:]
        for bin in (profile.neutralAxisBins ?? []) where bin.coveragePct >= 0.02 {
            result[Int((bin.lumaCenter * 100).rounded())] = (bin.labA, bin.labB)
        }
        return result
    }

    static func relativeNeutralBins(from pairs: [MatchedProfilePair]) -> [NeutralBin] {
        var byLuma: [Int: [(a: Double, b: Double)]] = [:]
        for pair in pairs {
            let mine = binsByLuma(pair.mine)
            let other = binsByLuma(pair.other)
            for (key, myBin) in mine {
                guard let otherBin = other[key] else { continue }
                byLuma[key, default: []].append((
                    a: (myBin.a - otherBin.a) / 2.0,
                    b: (myBin.b - otherBin.b) / 2.0
                ))
            }
        }
        return byLuma.sorted { $0.key < $1.key }.compactMap { key, values in
            let a = consistentRelativeMedian(values.map(\.a))
            let b = consistentRelativeMedian(values.map(\.b))
            guard abs(a) > 1e-6 || abs(b) > 1e-6 else { return nil }
            return NeutralBin(
                luma: Double(key) / 100.0,
                a: clamp(a, -4.0, 4.0),
                b: clamp(b, -4.0, 4.0)
            )
        }
    }

    private static func hueBinsByAngle(_ profile: ScannerProfile) -> [Int: ScannerProfileHueResponseBin] {
        var result: [Int: ScannerProfileHueResponseBin] = [:]
        for bin in profile.hueResponse ?? [] {
            let key = Int(bin.labHueDegrees.rounded())
            if result[key] == nil { result[key] = bin }
        }
        return result
    }

    static func relativeHueAnchors(from pairs: [MatchedProfilePair]) -> [HueAnchor] {
        var byAngle: [Int: [(angle: Double, logGain: Double, rotation: Double)]] = [:]
        for pair in pairs {
            let mine = hueBinsByAngle(pair.mine)
            let other = hueBinsByAngle(pair.other)
            for (key, myBin) in mine {
                guard let otherBin = other[key],
                      myBin.chromaGain.isFinite, otherBin.chromaGain.isFinite,
                      myBin.chromaGain > 0, otherBin.chromaGain > 0 else { continue }
                byAngle[key, default: []].append((
                    angle: (myBin.labHueDegrees + otherBin.labHueDegrees) / 2.0,
                    logGain: (log(myBin.chromaGain) - log(otherBin.chromaGain)) / 2.0,
                    rotation: (myBin.hueRotateDegrees - otherBin.hueRotateDegrees) / 2.0
                ))
            }
        }
        return byAngle.sorted { $0.key < $1.key }.compactMap { _, values in
            guard let angle = median(values.map(\.angle)) else { return nil }
            let gain = exp(consistentRelativeMedian(values.map(\.logGain)))
            let rotation = consistentRelativeMedian(values.map(\.rotation))
            return HueAnchor(
                hueDegrees: angle,
                chromaGain: clamp(gain, hueChromaGainRange.lowerBound, hueChromaGainRange.upperBound),
                rotateDegrees: clamp(rotation, -hueRotateLimit, hueRotateLimit)
            )
        }
    }

    /// tone 배열에서 p50 knot 의 index.
    static let toneMidIndex = 4

    /// 실측 톤 knot 의 노출 재앵커: 측정 mid → newMid 로 옮기되 linear 스탑 오프셋을
    /// 보존한다(섀도 1:1). 하이라이트 오프셋은 새 mid 의 가용 헤드룸(0.99 까지)에 맞춰
    /// 압축만 한다(확장 금지) — 측정 숄더의 상대 간격(하이라이트 롤오프 프로파일)은
    /// 유지된다. 재앵커는 단조를 보존한다.
    static func exposureReanchoredTone(_ tone: [Double], toMid newMid: Double) -> [Double] {
        guard tone.indices.contains(toneMidIndex) else { return tone }
        let oldMidLin = srgbDecode(clamp(tone[toneMidIndex], 0.002, 0.998))
        let newMidLin = srgbDecode(clamp(newMid, 0.1, 0.9))
        guard oldMidLin > 1e-6 else { return tone }
        let capLin = srgbDecode(0.99)
        let topLin = max(srgbDecode(clamp(tone[tone.count - 1], 0.002, 0.998)), oldMidLin)
        let measuredHeadroom = log2(max(topLin / oldMidLin, 1.0 + 1e-9))
        let availableHeadroom = log2(capLin / newMidLin)
        let highScale = measuredHeadroom > availableHeadroom
            ? availableHeadroom / measuredHeadroom
            : 1.0
        return tone.map { y in
            let lin = max(srgbDecode(clamp(y, 0.002, 0.998)), 1e-6)
            var stops = log2(lin / oldMidLin)
            if stops > 0 { stops *= highScale }
            return clamp(srgbEncode(newMidLin * pow(2.0, stops)), 0.002, 0.998)
        }
    }

    /// 사용자가 NORITSU/FUJI 타깃을 직접 선택했을 때 쓰는 결정적 상대 시그니처.
    /// tone/neutral/hue/chroma 모두 두 스캐너의 같은 source roll-label set에서만 유도한다.
    /// roll-label pair가 없으면 nil을 반환해 실제 렌더가 no-op이 되며, 장치 이름이나 서로 다른
    /// 장면의 절대 통계로 색을 꾸며내지 않는다. 현재 schema에는 frame ID/hash가 없으므로
    /// 이것은 고정된 realOnly 출력 통계 기반 상대 에뮬레이션이지 장치 정확 복제가 아니다.
    static func scannerSignature(
        scanner: String,
        filmType: FilmType = .colorNegative,
        profiles: [ScannerProfile],
        filmKey: String? = nil
    ) -> Signature? {
        let preferredKind: String
        switch filmType {
        case .colorNegative, .bwNegative:
            preferredKind = "color nega"
        case .colorPositive, .bwPositive:
            preferredKind = "color slide"
        }
        let pairs = matchedProfilePairs(
            scanner: scanner,
            kind: preferredKind,
            profiles: profiles,
            filmKey: filmKey
        )
        guard !pairs.isEmpty else { return nil }

        func toneValue(_ profile: ScannerProfile, index: Int) -> Double {
            let key = toneKeys[index]
            return clamp(
                profile.tone[key]?.median ?? srgbEncode(designPercentiles[index]),
                0.002,
                0.998
            )
        }

        // 두 실기 percentile의 중점을 공통 입력 knot로 삼고, 각 pair의 절반 차이만
        // 대칭 분배한다. roll 내용과 실기 절대 AE는 중점 재앵커에서 제거된다.
        let consensus = (0..<designPercentiles.count).map { index in
            median(pairs.map {
                (toneValue($0.mine, index: index) + toneValue($0.other, index: index)) / 2.0
            }) ?? designToneXs[index]
        }
        let toneXs = exposureReanchoredTone(consensus, toMid: photometricMidTone)
        let tone = (0..<designPercentiles.count).map { index in
            let halfDelta = consistentRelativeMedian(pairs.map {
                (toneValue($0.mine, index: index) - toneValue($0.other, index: index)) / 2.0
            })
            return clamp(toneXs[index] + halfDelta, 0.002, 0.998)
        }

        // pair마다 √(mine/other)를 먼저 구한다. 서로 다른 필름 pair에서 방향이 뒤집히는
        // 대역은 consistentRelativeMedian이 0으로 돌려 장치 특성으로 오인하지 않는다.
        let bandKeys: [(key: String, luma: Double)] = [
            ("shadow_chroma", 0.165), ("mid_chroma", 0.495), ("high_chroma", 0.83),
        ]
        let chromaBands = bandKeys.map { band in
            let logHalfRatios = pairs.compactMap { pair -> Double? in
                guard let mine = pair.mine.color[band.key]?.median,
                      let other = pair.other.color[band.key]?.median,
                      mine.isFinite, other.isFinite, mine > 1e-3, other > 1e-3 else { return nil }
                return (log(mine) - log(other)) / 2.0
            }
            let gain = exp(consistentRelativeMedian(logHalfRatios))
            return ChromaBand(
                luma: band.luma,
                gain: clamp(gain, chromaBandGainRange.lowerBound, chromaBandGainRange.upperBound)
            )
        }

        let neutralBins = relativeNeutralBins(from: pairs)
        let hueAnchors = relativeHueAnchors(from: pairs)
        return Signature(
            toneXs: toneXs,
            tone: tone,
            neutralBins: neutralBins,
            hueAnchors: hueAnchors,
            chromaBands: chromaBands
        )
    }

    static func scannerName(for target: DevelopTarget) -> String? {
        switch target {
        case .noritsu: return "NORITSU"
        case .sp3000: return "SP-3000"
        // F135/HR 는 번들 실측 corpus 가 없다 → 실측 상대 차분 레이어 없이 문서 개성만 적용.
        case .main, .print, .rescue, .f135, .hr: return nil
        }
    }

    /// 실기 색 시그니처를 문서화된 색과학 + QA 로 물리적으로 타당하게 정제한다. 측정 시그니처의
    /// 방향은 유지하되, 대칭 분배·베이스 상호작용이 만든 아티팩트를 교정한다. 전 이미지에 동일
    /// 규칙으로 적용되며 특정 컷 보정이 아니다.
    ///
    ///  • NORITSU(문서화된 "중립 기준" 스캐너): NOR/SP 대칭 분배가 만든 초록(a*<0) 드리프트를
    ///    크게 줄여 중립화한다.
    ///  • FUJI(SP-3000): 하이라이트로 갈수록 강해지는 레드(a*>0) 특성은 그대로 유지된다.
    ///  • 암부 웜캐스트(빨강/노랑) 제거는 픽셀 luma 기준이라 ColorCube 적용부에서 처리한다(bin
    ///    단위로는 최저 bin 아래 암부가 미드 값을 물려받아 taper 되지 않는다).
    ///  • (2026-07-20) 과거의 NORITSU 채도 ×1.14 부스트는 제거 — documented 레이어가 없던
    ///    시절 "밋밋함 완화" 땜질로, 문서화된 muted 채도 개성(documentedCharacter)과 정반대로
    ///    싸우며 상쇄됐다. 절대 개성은 documented 가, 이 레이어는 실측 상대 성분만 소유한다.
    static func characterRefined(_ sig: Signature, target: DevelopTarget) -> Signature {
        var s = sig
        if target == .noritsu {
            s.neutralBins = sig.neutralBins.map { bin in
                NeutralBin(luma: bin.luma, a: bin.a < 0 ? bin.a * 0.22 : bin.a, b: bin.b)
            }
        }
        return s
    }

    // MARK: 프로파일 해석 (수동 > 검증된 필름 매칭 > 검증된 스캐너 공통)

    private static let signatureCacheLock = NSLock()
    private nonisolated(unsafe) static var signatureCache: [String: Signature] = [:]

    static func resolveSignature(target: DevelopTarget, params: DevelopParameters) -> Signature? {
        guard let scanner = scannerName(for: target) else { return nil }
        let cacheKey = "\(scanner)|\(params.scannerProfileID ?? "")|\(params.filmStockDminID ?? "")|\(params.filmType.rawValue)"
        signatureCacheLock.lock()
        if let cached = signatureCache[cacheKey] {
            signatureCacheLock.unlock()
            return cached
        }
        signatureCacheLock.unlock()

        var resolved: Signature?
        switch params.filmType {
        case .colorNegative, .bwNegative:
            resolved = negativeSignature(scanner: scanner, target: target, params: params)
        case .colorPositive, .bwPositive:
            // 포지티브는 절대 percentile 이식(롤 내용 편향) 대신 항등 기준 상대 시그니처를
            // 쓴다 — 수동 프로파일/필름 매칭 우선순위는 네거티브 전용이다.
            resolved = positiveSignature(
                scanner: scanner,
                profiles: ScannerProfileRegistry.loadAll()
            )
        }
        // 흑백: 색 성분 제거. 현재 프로파일에는 장치별 흑백 틴트 측정값이 없으므로
        // 문헌의 방향만 보고 고정 색을 만들지 않는다.
        if params.filmType == .bwNegative || params.filmType == .bwPositive {
            if var sig = resolved {
                sig.hueAnchors = []
                sig.chromaBands = []   // 흑백은 luma 붕괴 — 채도 변조 무의미
                sig.neutralBins = []
                resolved = sig
            }
        } else if let sig = resolved {
            resolved = characterRefined(sig, target: target)
        }
        if let resolved {
            signatureCacheLock.lock()
            signatureCache[cacheKey] = resolved
            signatureCacheLock.unlock()
        }
        return resolved
    }

    /// 네거티브(컬러/흑백) 시그니처. 수동/자동 필름을 선택한 경우에는 그 필름의 exact
    /// roll-label pair가 있을 때만 상대 시그니처를 반환한다. 선택 근거가 불완전하면 공통
    /// 시그니처로 바꾸지 않고 nil(MAIN과 같은 no-op)을 반환한다.
    private static func negativeSignature(
        scanner: String,
        target: DevelopTarget,
        params: DevelopParameters
    ) -> Signature? {
        let all = ScannerProfileRegistry.loadAll()

        // 1. 수동 선택: 대상 스캐너의 선택 프로파일이 paired evidence를 가질 때만 사용.
        if let id = params.scannerProfileID {
            guard let profile = all.first(where: { $0.id == id && $0.scanner == scanner }) else {
                return nil
            }
            return scannerSignature(
                scanner: scanner,
                filmType: params.filmType,
                profiles: all,
                filmKey: profile.filmKey
            )
        }

        // 2. 자동 필름 매칭: pairedValidated 프로파일만 matcher가 반환하며, 여기서도 다시
        // roll-label pair를 요구한다.
        if params.filmStockDminID != nil {
            guard let matched = ScannerProfileMatcher.preferredProfileID(
               target: target,
               filmType: params.filmType,
               filmStockDminID: params.filmStockDminID,
               currentID: nil,
               profiles: all
            ), let profile = all.first(where: { $0.id == matched && $0.scanner == scanner }) else {
                return nil
            }
            return scannerSignature(
                scanner: scanner,
                filmType: params.filmType,
                profiles: all,
                filmKey: profile.filmKey
            )
        }

        // 3. 스캐너 공통: 모든 roll-label matched film group의 일관된 상대 성분.
        return scannerSignature(scanner: scanner, filmType: params.filmType, profiles: all)
    }
}
