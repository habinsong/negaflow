import XCTest
import CoreImage
@testable import Chromabase

/// NORITSU HS-1800 / FUJI SP-3000 독자 타겟(2026-07-05 정밀 시그니처) 검증 —
/// 합성 픽스처 + 수치 측정.
///   • 명칭/사이드카 호환
///   • 실측 프로파일(schemaVersion 2) → 시그니처 집계/해석 우선순위
///   • 감마 도메인 정합: 실측 percentile 이 최종 sRGB 출력에 그대로 나타나는지
///   • 중립축 드리프트 / hue 시그니처 이식 + 끝점 중립 보존
///   • 독자 베이스가 main 과 분리되고 두 스캐너가 서로 다르며 결정적임
final class ScannerTargetGradeTests: XCTestCase {

    // MARK: 명칭/호환

    func testTargetDisplayNamesAndRawValuesStayCompatible() {
        XCTAssertEqual(DevelopTarget.main.displayName, "MAIN")
        XCTAssertEqual(DevelopTarget.print.displayName, "PRINT")
        XCTAssertEqual(DevelopTarget.noritsu.displayName, "HS")
        XCTAssertEqual(DevelopTarget.sp3000.displayName, "SP")
        // rawValue 는 sidecar/XMP 호환을 위해 유지되어야 한다.
        XCTAssertEqual(DevelopTarget.noritsu.rawValue, "noritsu")
        XCTAssertEqual(DevelopTarget.sp3000.rawValue, "sp-3000")
        XCTAssertTrue(DevelopTarget.noritsu.isScannerEmulation)
        XCTAssertTrue(DevelopTarget.sp3000.isScannerEmulation)
        XCTAssertFalse(DevelopTarget.main.isScannerEmulation)
        XCTAssertFalse(DevelopTarget.print.isScannerEmulation)
    }

    // MARK: 시그니처 집계/해석

    func testScannerSignatureAggregatesExplicitRealProfiles() throws {
        let all = ScannerProfileRegistry.loadAll()
        guard !all.isEmpty else { throw XCTSkip("번들 스캐너 프로파일 없음") }
        XCTAssertTrue(all.allSatisfy { $0.validationStatus == .realOnly })
        guard let noritsu = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: all),
              let sp = ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: all) else {
            return XCTFail("스캐너 공통 시그니처 집계 실패")
        }
        // 실측 경향: SP-3000 은 NORITSU 보다 미드톤(p50)이 밝다(같은 롤 실측 쌍 포함 데이터).
        let p50Index = 4
        XCTAssertGreaterThan(sp.tone[p50Index], noritsu.tone[p50Index],
            "SP-3000 실측 p50 이 NORITSU 보다 높아야 한다. sp=\(sp.tone[p50Index]) nor=\(noritsu.tone[p50Index])")
        for sig in [noritsu, sp] {
            XCTAssertEqual(sig.tone.count, ScannerTargetGrade.designPercentiles.count)
            // 톤 percentile 중앙값은 0...1 이고 단조 증가해야 한다(실측 분포의 성질).
            XCTAssertGreaterThan(sig.tone.first!, 0.0)
            XCTAssertLessThan(sig.tone.last!, 1.0)
            for i in 1..<sig.tone.count {
                XCTAssertGreaterThan(sig.tone[i], sig.tone[i - 1],
                    "percentile 중앙값은 단조여야 한다: \(sig.tone)")
            }
            // schemaVersion 2 실측 필드가 집계에 실려야 한다.
            XCTAssertFalse(sig.neutralBins.isEmpty, "중립축 드리프트 bin 이 있어야 한다")
            XCTAssertFalse(sig.hueAnchors.isEmpty, "hue 시그니처 앵커가 있어야 한다")
        }
        // hue 시그니처는 같은 롤 쌍에서 대칭 분배되므로 두 스캐너가 서로 반대 방향이어야 한다.
        // (예: SP 시안-블루 채도↑ ↔ NOR ↓)
        let spBlue = ScannerTargetGrade.hueResponse(at: 239.0, anchors: sp.hueAnchors)
        let norBlue = ScannerTargetGrade.hueResponse(at: 239.0, anchors: noritsu.hueAnchors)
        XCTAssertGreaterThan(spBlue.gain, norBlue.gain,
            "실측: SP-3000 이 시안-블루 채도를 더 강하게 렌더링한다")
    }

    func testScannerSignatureRejectsDraftProfiles() throws {
        let all = ScannerProfileRegistry.loadAll().map { profile in
            var profile = profile
            profile.validationStatus = .draft
            return profile
        }
        guard !all.isEmpty else { throw XCTSkip("번들 스캐너 프로파일 없음") }

        XCTAssertNil(ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: all))
        XCTAssertNil(ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: all))
    }

    func testResolveSignatureRequiresExactSelectedPairAndUsesCommonOnlyWhenBare() throws {
        let all = ScannerProfileRegistry.loadAll()
        guard let spProfile = ScannerTargetGrade.matchedProfilePairs(
                  scanner: "SP-3000", kind: "color nega", profiles: all
              ).first?.mine,
              let norProfile = all.first(where: { $0.scanner == "NORITSU" && $0.kind == "color nega" }) else {
            throw XCTSkip("번들 프로파일 부족")
        }
        // 1. 수동 선택도 절대 프로파일을 직접 이식하지 않고, 해당 필름의 roll-label pair
        // 상대 시그니처만 사용한다.
        var manual = DevelopParameters()
        manual.developTarget = .sp3000
        manual.scannerProfileID = spProfile.id
        guard let manualSig = ScannerTargetGrade.resolveSignature(target: .sp3000, params: manual) else {
            return XCTFail("수동 선택 해석 실패")
        }
        guard let paired = ScannerTargetGrade.scannerSignature(
            scanner: "SP-3000",
            profiles: all,
            filmKey: spProfile.filmKey
        ) else { return XCTFail("수동 선택 pair 시그니처 실패") }
        XCTAssertEqual(manualSig, paired)

        // 2. 선택한 ID가 타 스캐너이거나 exact pair 근거가 없으면 다른 필름의 공통
        // 시그니처로 바꾸지 않고 MAIN과 같은 no-op(nil)이어야 한다.
        var wrong = DevelopParameters()
        wrong.developTarget = .sp3000
        wrong.scannerProfileID = norProfile.id
        XCTAssertNil(ScannerTargetGrade.resolveSignature(target: .sp3000, params: wrong))

        let pairedFilmKeys = Set(ScannerTargetGrade.matchedProfilePairs(
            scanner: "SP-3000", kind: "color nega", profiles: all
        ).map { $0.mine.filmKey })
        if let unpaired = all.first(where: {
            $0.scanner == "SP-3000" && $0.kind == "color nega"
                && !pairedFilmKeys.contains($0.filmKey)
        }) {
            var unpairedManual = DevelopParameters()
            unpairedManual.developTarget = .sp3000
            unpairedManual.scannerProfileID = unpaired.id
            XCTAssertNil(
                ScannerTargetGrade.resolveSignature(target: .sp3000, params: unpairedManual),
                "선택 필름 exact pair가 없으면 공통 signature로 폴백하면 안 된다"
            )
        }

        // 3. 자동 필름 매칭 근거가 없을 때도 공통 시그니처로 폴백하지 않는다.
        var film = DevelopParameters()
        film.developTarget = .noritsu
        film.filmStockDminID = "kodak-portra-160"
        XCTAssertNil(ScannerProfileMatcher.preferredProfileID(
            target: .noritsu,
            filmType: .colorNegative,
            filmStockDminID: film.filmStockDminID,
            currentID: nil,
            profiles: all
        ))
        XCTAssertNil(ScannerTargetGrade.resolveSignature(target: .noritsu, params: film))

        // 4. 타겟 선택 자체가 명시적 opt-in이므로 추가 프로파일 선택 없이 공통 시그니처가 있어야 한다.
        var bare = DevelopParameters()
        bare.developTarget = .sp3000
        let bareSig = ScannerTargetGrade.resolveSignature(target: .sp3000, params: bare)
        XCTAssertNotNil(bareSig)

        // 5. 비-에뮬레이션 타겟은 nil.
        XCTAssertNil(ScannerTargetGrade.resolveSignature(target: .main, params: DevelopParameters()))
    }

    func testRollLabelNormalizationMatchesPortableCompilerContract() {
        let tone = [0.06, 0.10, 0.15, 0.30, 0.60, 0.80, 0.90, 0.93, 0.96]
        let portable = [
            makeNegaProfile(
                scanner: "NORITSU",
                filmKey: "portable",
                imageCount: 40,
                tone: tone,
                rolls: [" \t\r\n\u{000B}\u{000C}ROLL A\u{000C}", "scope\\ROLL B"]
            ),
            makeNegaProfile(
                scanner: "SP-3000",
                filmKey: "portable",
                imageCount: 40,
                tone: tone,
                rolls: ["roll a", "scope/roll b"]
            ),
        ]
        XCTAssertTrue(
            ScannerTargetGrade.hasMatchedRollLabelProvenance(portable[0], portable[1]),
            "ASCII case·6종 ASCII trim·slash 정규화는 컴파일러와 같아야 한다"
        )

        let nonPortable = [
            makeNegaProfile(
                scanner: "NORITSU", filmKey: "unicode", imageCount: 40,
                tone: tone, rolls: ["Straße"]
            ),
            makeNegaProfile(
                scanner: "SP-3000", filmKey: "unicode", imageCount: 40,
                tone: tone, rolls: ["Straße"]
            ),
        ]
        XCTAssertFalse(
            ScannerTargetGrade.hasMatchedRollLabelProvenance(nonPortable[0], nonPortable[1]),
            "비 ASCII provenance는 Python/Swift Unicode 버전에 기대지 말고 fail-closed해야 한다"
        )
    }

    // MARK: 노출 재앵커 / 같은 롤 쌍 톤 집계

    /// 노출 재앵커: mid 는 정확히 newMid 로, 섀도는 mid 기준 linear 스탑 오프셋 보존,
    /// 하이라이트는 가용 헤드룸으로 압축만 하고 단조를 유지해야 한다.
    func testExposureReanchoredToneMovesMidAndPreservesShadowStops() {
        let tone = [0.075, 0.106, 0.152, 0.284, 0.571, 0.787, 0.895, 0.928, 0.959]
        let newMid = 0.692
        let anchored = ScannerTargetGrade.exposureReanchoredTone(tone, toMid: newMid)
        XCTAssertEqual(anchored[ScannerTargetGrade.toneMidIndex], newMid, accuracy: 1e-9)
        // 섀도(온전 보존): mid 기준 스탑 오프셋이 그대로여야 한다.
        let oldMidLin = ScannerTargetGrade.srgbDecode(tone[4])
        let newMidLin = ScannerTargetGrade.srgbDecode(newMid)
        for i in 0..<4 {
            let oldStops = log2(ScannerTargetGrade.srgbDecode(tone[i]) / oldMidLin)
            let newStops = log2(ScannerTargetGrade.srgbDecode(anchored[i]) / newMidLin)
            XCTAssertEqual(newStops, oldStops, accuracy: 1e-6,
                "섀도 스탑 오프셋이 보존되어야 한다 (index \(i))")
        }
        // 하이라이트: 0.99 이하로 압축되고 순서(단조)가 유지된다.
        for i in 5..<anchored.count {
            XCTAssertLessThanOrEqual(anchored[i], 0.99 + 1e-9)
            XCTAssertGreaterThan(anchored[i], anchored[i - 1])
        }
        // 재앵커가 이미 mid 에 있으면 항등에 가깝다.
        let identity = ScannerTargetGrade.exposureReanchoredTone(tone, toMid: tone[4])
        for (a, b) in zip(identity, tone) {
            XCTAssertEqual(a, b, accuracy: 1e-9)
        }
    }

    private func makeNegaProfile(
        scanner: String,
        filmKey: String,
        imageCount: Int,
        tone: [Double],
        bandChroma: (shadow: Double, mid: Double, high: Double)? = nil,
        clipWhitePct: Double? = nil,
        rolls: [String] = ["roll-01"],
        neutralBins: [ScannerProfileNeutralBin] = [],
        hueResponse: [ScannerProfileHueResponseBin]? = nil
    ) -> ScannerProfile {
        var toneStats: [String: ScannerProfileStat] = [:]
        for (index, key) in ScannerTargetGrade.toneKeys.enumerated() {
            toneStats[key] = makeStat(tone[index])
        }
        if let clipWhitePct {
            toneStats["clip_white_pct"] = makeStat(clipWhitePct)
        }
        var colorStats: [String: ScannerProfileStat] = [:]
        if let bandChroma {
            colorStats["shadow_chroma"] = makeStat(bandChroma.shadow)
            colorStats["mid_chroma"] = makeStat(bandChroma.mid)
            colorStats["high_chroma"] = makeStat(bandChroma.high)
        }
        return ScannerProfile(
            schemaVersion: 2,
            id: "\(scanner)-nega-\(filmKey)",
            displayName: "\(scanner) nega \(filmKey)",
            scanner: scanner,
            kind: "color nega",
            filmKey: filmKey,
            validationStatus: .realOnly,
            rollCount: rolls.count,
            imageCount: imageCount,
            singleRollLimited: rolls.count == 1,
            // hasMatchedRollProvenance 가 요구하는 형태: scanner 세그먼트 뒤에 roll 경로.
            sourceProfiles: rolls.map { "profiles/\(scanner)/\($0)/aggregate.json" },
            tone: toneStats,
            color: colorStats,
            neutralAxis: [:],
            neutralAxisBins: neutralBins,
            hueResponse: hueResponse,
            texture: ["texture_sharpness_p95": makeStat(0.40)],
            sceneBuckets: [],
            coverageCandidates: [],
            profileHash: "sha256:test"
        )
    }

    /// 톤은 source roll provenance 가 명시적으로 일치하는 쌍 필름만 집계하고, 어두운 롤
    /// (unpaired) 내용이 공통 시그니처의 노출을 오염시키면 안 된다.
    /// mid 는 설계 앵커 ± 실기 간 차이 절반.
    func testScannerSignatureToneUsesOnlySameRollPairFilms() {
        let paired = [0.06, 0.10, 0.15, 0.30, 0.60, 0.80, 0.90, 0.93, 0.96]
        let pairedOther = paired.map { min($0 + 0.06, 0.99) }   // 상대 실기가 일관되게 밝음
        let darkRoll = [0.02, 0.03, 0.05, 0.08, 0.14, 0.25, 0.45, 0.70, 0.95]
        let profiles = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "pair-film", imageCount: 40, tone: paired),
            makeNegaProfile(scanner: "SP-3000", filmKey: "pair-film", imageCount: 38, tone: pairedOther),
            // 야간 롤: 쌍 없음(상대 실기에 같은 롤 provenance 없음) → 톤 집계에서 제외.
            makeNegaProfile(scanner: "NORITSU", filmKey: "night-roll", imageCount: 38, tone: darkRoll,
                            rolls: ["night-roll-only"]),
        ]
        guard let sig = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: profiles) else {
            return XCTFail("공통 시그니처 집계 실패")
        }
        // halfDelta = (0.60 − 0.66)/2 = −0.03 → mid = photometric 앵커(srgbEncode(0.18)) − 0.03.
        // (2026-07-17: 설계 앵커가 linear 0.5 가정에서 photometric mid 로 교정됨.)
        let expectedMid = ScannerTargetGrade.photometricMidTone - 0.03
        XCTAssertEqual(sig.tone[ScannerTargetGrade.toneMidIndex], expectedMid, accuracy: 1e-6,
            "톤 mid 는 쌍 필름 실측 차이의 대칭 분배여야 한다(야간 롤 무영향)")
        // 야간 롤을 빼도 톤이 동일해야 한다(쌍 필름만 반영).
        let withoutDark = ScannerTargetGrade.scannerSignature(
            scanner: "NORITSU", profiles: Array(profiles.prefix(2)))
        XCTAssertEqual(sig.tone, withoutDark?.tone, "unpaired 롤은 톤에 영향이 없어야 한다")

        // source roll-label provenance가 다르면 쌍이 아니다(filmKey/이미지 수 유사성은
        // 근거가 아니다) → 장치 특성을 만들지 않고 nil/no-op.
        let unpaired = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "solo", imageCount: 40, tone: paired,
                            rolls: ["solo-roll-a"]),
            makeNegaProfile(scanner: "SP-3000", filmKey: "solo", imageCount: 80, tone: pairedOther,
                            rolls: ["solo-roll-b"]),
        ]
        XCTAssertNil(ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: unpaired),
                     "roll-label pair가 없으면 전체 ScannerTargetGrade가 no-op이어야 한다")

        // label이 같아도 관찰 수가 크게 다르면 서로 다른 장면 표본일 가능성이 높으므로
        // compiler와 동일한 ±15% coverage guard에서 거부한다.
        let coverageMismatch = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "same-label", imageCount: 40, tone: paired),
            makeNegaProfile(scanner: "SP-3000", filmKey: "same-label", imageCount: 20, tone: pairedOther),
        ]
        XCTAssertNil(
            ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: coverageMismatch),
            "관찰 수가 크게 다른 roll-label corpus는 상대 시그니처 근거가 아니어야 한다"
        )
    }

    func testScannerSignatureNeutralAndHueUseOnlyRollLabelPairs() {
        let tone = [0.06, 0.10, 0.15, 0.30, 0.60, 0.80, 0.90, 0.93, 0.96]
        let norBin = ScannerProfileNeutralBin(
            lumaCenter: 0.55, coveragePct: 0.5, labA: -2.0, labB: 1.0
        )
        let spBin = ScannerProfileNeutralBin(
            lumaCenter: 0.55, coveragePct: 0.5, labA: 2.0, labB: -1.0
        )
        let norHue = ScannerProfileHueResponseBin(
            labHueDegrees: 30, chromaGain: 1.2, hueRotateDegrees: -2.0, weight: 3.0
        )
        let spHue = ScannerProfileHueResponseBin(
            labHueDegrees: 30, chromaGain: 1.0 / 1.2, hueRotateDegrees: 2.0, weight: 3.0
        )
        let pair = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "paired", imageCount: 30,
                            tone: tone, neutralBins: [norBin], hueResponse: [norHue]),
            makeNegaProfile(scanner: "SP-3000", filmKey: "paired", imageCount: 30,
                            tone: tone, neutralBins: [spBin], hueResponse: [spHue]),
        ]
        let unpaired = makeNegaProfile(
            scanner: "NORITSU",
            filmKey: "unpaired",
            imageCount: 30,
            tone: tone,
            rolls: ["different-roll"],
            neutralBins: [ScannerProfileNeutralBin(
                lumaCenter: 0.55, coveragePct: 1.0, labA: 90, labB: -90
            )],
            hueResponse: [ScannerProfileHueResponseBin(
                labHueDegrees: 30, chromaGain: 1.8, hueRotateDegrees: 8, weight: 100
            )]
        )
        guard let baseline = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: pair),
              let withUnpaired = ScannerTargetGrade.scannerSignature(
                  scanner: "NORITSU", profiles: pair + [unpaired]
              ) else { return XCTFail("paired 시그니처 생성 실패") }

        XCTAssertEqual(withUnpaired, baseline, "unpaired neutral/hue가 상대 시그니처를 오염시키면 안 된다")
        guard let neutral = baseline.neutralBins.first,
              let hue = baseline.hueAnchors.first else {
            return XCTFail("paired neutral/hue 성분 누락")
        }
        XCTAssertEqual(neutral.a, -2.0, accuracy: 1e-9)
        XCTAssertEqual(neutral.b, 1.0, accuracy: 1e-9)
        XCTAssertEqual(hue.chromaGain, 1.2, accuracy: 1e-9)
        XCTAssertEqual(hue.rotateDegrees, -2.0, accuracy: 1e-9)
    }

    /// 같은 롤 라벨 쌍의 대역 채도 차이가 대칭 분배된 상대 성분으로 들어와야 한다.
    func testScannerSignatureDerivesChromaBandsFromPairs() {
        let tone = [0.06, 0.10, 0.15, 0.30, 0.60, 0.80, 0.90, 0.93, 0.96]
        let profiles = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "pair", imageCount: 40, tone: tone,
                            bandChroma: (shadow: 16.8, mid: 20.5, high: 15.3), clipWhitePct: 5.2),
            makeNegaProfile(scanner: "SP-3000", filmKey: "pair", imageCount: 38,
                            tone: tone.map { min($0 + 0.05, 0.99) },
                            bandChroma: (shadow: 16.9, mid: 46.0, high: 26.4), clipWhitePct: 0.2),
        ]
        guard let nor = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: profiles),
              let sp = ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: profiles) else {
            return XCTFail("시그니처 집계 실패")
        }
        XCTAssertEqual(nor.chromaBands.count, 3)
        XCTAssertEqual(sp.chromaBands.count, 3)
        // mid 대역: √(20.5/46.0) ≈ 0.667 / √(46.0/20.5) ≈ 1.498 — 대칭(곱 ≈ 1).
        XCTAssertEqual(nor.chromaBands[1].gain, (20.5 / 46.0).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(sp.chromaBands[1].gain, (46.0 / 20.5).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(nor.chromaBands[1].gain * sp.chromaBands[1].gain, 1.0, accuracy: 0.01,
            "대역 채도는 실기 간 대칭 분배여야 한다")
        // shadow 대역은 실측상 실기 간 차이가 없다(≈1.0).
        XCTAssertEqual(nor.chromaBands[0].gain, 1.0, accuracy: 0.02)

        // 쌍이 없으면(source roll provenance 불일치) 캐릭터 없음.
        let unpaired = [
            makeNegaProfile(scanner: "NORITSU", filmKey: "solo", imageCount: 40, tone: tone,
                            bandChroma: (shadow: 16.8, mid: 20.5, high: 15.3), clipWhitePct: 5.2,
                            rolls: ["solo-roll-a"]),
            makeNegaProfile(scanner: "SP-3000", filmKey: "solo", imageCount: 90, tone: tone,
                            bandChroma: (shadow: 16.9, mid: 46.0, high: 26.4), clipWhitePct: 0.2,
                            rolls: ["solo-roll-b"]),
        ]
        XCTAssertNil(ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: unpaired),
                     "쌍 없이 대역 채도뿐 아니라 전체 장치 캐릭터를 만들면 안 된다")
    }

    /// 대역 채도 배율이 미드 유채색에 적용되고, 순흑/순백 부근은 테이퍼로 불변이어야 한다.
    func testChromaBandGainScalesMidtonesAndKeepsEndpoints() {
        let vivid = ScannerTargetGrade.Signature(
            tone: designIdentityTone(), neutralBins: [], hueAnchors: [],
            chromaBands: [
                ScannerTargetGrade.ChromaBand(luma: 0.165, gain: 1.0),
                ScannerTargetGrade.ChromaBand(luma: 0.495, gain: 1.5),
                ScannerTargetGrade.ChromaBand(luma: 0.83, gain: 1.31),
            ])
        let neutral = ScannerTargetGrade.Signature(
            tone: designIdentityTone(), neutralBins: [], hueAnchors: [])
        let width = 3, height = 1
        // 미드 유채색(스킨 톤) / 순백 근처 / 순흑 근처.
        let img = makeLinearImage(width: width, height: height) { x, _ in
            switch x {
            case 0: return (0.32, 0.18, 0.10)
            case 1: return (0.97, 0.97, 0.97)
            default: return (0.008, 0.008, 0.008)
            }
        }
        func chroma(_ px: [UInt8], _ x: Int) -> Double {
            let lab = ScannerTargetGrade.srgbToLab(
                r: Double(px[x * 4]) / 255.0,
                g: Double(px[x * 4 + 1]) / 255.0,
                b: Double(px[x * 4 + 2]) / 255.0)
            return (lab.a * lab.a + lab.b * lab.b).squareRoot()
        }
        let graded = renderSRGB8(ScannerTargetGrade.apply(to: img, signature: vivid, target: .main),
                                 width: width, height: height)
        let base = renderSRGB8(ScannerTargetGrade.apply(to: img, signature: neutral, target: .main),
                               width: width, height: height)
        XCTAssertGreaterThan(chroma(graded, 0), chroma(base, 0) * 1.15,
            "미드 유채색 채도가 대역 배율만큼 늘어야 한다")
        for x in [1, 2] {
            XCTAssertEqual(chroma(graded, x), chroma(base, x), accuracy: 2.0,
                "순백/순흑 부근은 테이퍼로 채도 변조가 없어야 한다 (x=\(x))")
        }
    }

    /// 번들 roll-label matched 출력 통계의 상대 방향을 보존한다: FUJI(SP-3000)는 미드
    /// 채도 배율 > 1, NORITSU는 < 1이다.
    func testBundledSignaturesCarryMeasuredScannerCharacter() throws {
        let all = ScannerProfileRegistry.loadAll()
        guard let nor = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: all),
              let sp = ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: all) else {
            throw XCTSkip("번들 프로파일 없음")
        }
        guard let norMid = nor.chromaBands.first(where: { abs($0.luma - 0.495) < 0.01 }),
              let spMid = sp.chromaBands.first(where: { abs($0.luma - 0.495) < 0.01 }) else {
            return XCTFail("mid 대역 채도 캐릭터가 있어야 한다")
        }
        XCTAssertGreaterThan(spMid.gain, 1.15, "FUJI 는 미드 채도가 살아야 한다(실측 vivid)")
        XCTAssertLessThan(norMid.gain, 0.9, "NORITSU 는 미드 채도가 차분해야 한다(실측)")
        // hue 시그니처: 확대된 클램프로 실측 캐릭터가 살아야 한다(예: NOR 레드 근방 gain > 1.2).
        let norRed = nor.hueAnchors.first { $0.hueDegrees < 10 }
        let spRed = sp.hueAnchors.first { $0.hueDegrees < 10 }
        if let norRed, let spRed {
            XCTAssertGreaterThan(norRed.chromaGain, 1.2, "NOR 레드 채도 실측(1.58)이 클램프에 잘리면 안 된다")
            XCTAssertLessThan(spRed.chromaGain, 0.8, "SP 레드 뮤트 실측(0.63)이 클램프에 잘리면 안 된다")
        }
    }

    func testBundledRelativeSignaturesAreReciprocalAndInputOrderIndependent() throws {
        let all = ScannerProfileRegistry.loadAll()
        let pairs = ScannerTargetGrade.matchedProfilePairs(
            scanner: "NORITSU", kind: "color nega", profiles: all
        )
        XCTAssertEqual(pairs.map { $0.mine.filmKey }, ["kodak ektar 100", "kodak portra 160"])

        guard let nor = ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: all),
              let sp = ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: all),
              let norReversed = ScannerTargetGrade.scannerSignature(
                  scanner: "NORITSU", profiles: Array(all.reversed())
              ) else { throw XCTSkip("번들 paired 시그니처 부족") }
        XCTAssertEqual(nor, norReversed, "입력 프로파일 순서가 결과를 바꾸면 안 된다")
        XCTAssertEqual(nor.toneXs, sp.toneXs, "두 장비는 같은 paired consensus knot를 공유해야 한다")
        for index in nor.tone.indices {
            XCTAssertEqual(
                (nor.tone[index] + sp.tone[index]) / 2.0,
                nor.toneXs[index],
                accuracy: 1e-9,
                "tone 상대 차이는 공통 knot 주위에 대칭이어야 한다 (index \(index))"
            )
        }

        XCTAssertEqual(nor.neutralBins.map(\.luma), sp.neutralBins.map(\.luma))
        for (lhs, rhs) in zip(nor.neutralBins, sp.neutralBins) {
            XCTAssertEqual(lhs.a + rhs.a, 0.0, accuracy: 1e-9)
            XCTAssertEqual(lhs.b + rhs.b, 0.0, accuracy: 1e-9)
        }
        XCTAssertEqual(nor.hueAnchors.map(\.hueDegrees), sp.hueAnchors.map(\.hueDegrees))
        for (lhs, rhs) in zip(nor.hueAnchors, sp.hueAnchors) {
            XCTAssertEqual(lhs.chromaGain * rhs.chromaGain, 1.0, accuracy: 2e-5)
            XCTAssertEqual(lhs.rotateDegrees + rhs.rotateDegrees, 0.0, accuracy: 1e-9)
        }
        XCTAssertEqual(nor.chromaBands.map(\.luma), sp.chromaBands.map(\.luma))
        for (lhs, rhs) in zip(nor.chromaBands, sp.chromaBands) {
            XCTAssertEqual(lhs.gain * rhs.gain, 1.0, accuracy: 1e-9)
        }
        // Ektar/Portra에서 방향이 뒤집힌 shadow/high chroma는 항등, mid만 공통 방향이다.
        XCTAssertEqual(nor.chromaBands[0].gain, 1.0, accuracy: 1e-12)
        XCTAssertLessThan(nor.chromaBands[1].gain, 1.0)
        XCTAssertEqual(nor.chromaBands[2].gain, 1.0, accuracy: 1e-12)
    }

    func testBundledInterpolatedRelativeComponentsStayPointwiseSymmetric() throws {
        let all = ScannerProfileRegistry.loadAll()
        let nor = try XCTUnwrap(ScannerTargetGrade.scannerSignature(scanner: "NORITSU", profiles: all))
        let fuji = try XCTUnwrap(ScannerTargetGrade.scannerSignature(scanner: "SP-3000", profiles: all))

        let toneXs = [0.0] + nor.toneXs + [1.0]
        let norTone = [0.0] + nor.tone + [1.0]
        let fujiTone = [0.0] + fuji.tone + [1.0]
        for index in 0...1_000 {
            let input = Double(index) / 1_000.0
            let norOutput = ScannerTargetGrade.relativeToneValue(
                at: input, xs: toneXs, ys: norTone
            )
            let fujiOutput = ScannerTargetGrade.relativeToneValue(
                at: input, xs: toneXs, ys: fujiTone
            )
            XCTAssertEqual(
                (norOutput + fujiOutput) / 2.0,
                input,
                accuracy: 1e-9,
                "tone 편차는 knot 사이에서도 공통 baseline 주위에 대칭이어야 한다"
            )
        }

        for hue in stride(from: 0.0, through: 360.0, by: 0.5) {
            let norGain = ScannerTargetGrade.hueResponse(at: hue, anchors: nor.hueAnchors).gain
            let fujiGain = ScannerTargetGrade.hueResponse(at: hue, anchors: fuji.hueAnchors).gain
            XCTAssertEqual(norGain * fujiGain, 1.0, accuracy: 1e-8, "hue=\(hue)")
        }
        for index in 0...1_000 {
            let luma = Double(index) / 1_000.0
            let norGain = ScannerTargetGrade.chromaBandGain(at: luma, bands: nor.chromaBands)
            let fujiGain = ScannerTargetGrade.chromaBandGain(at: luma, bands: fuji.chromaBands)
            XCTAssertEqual(norGain * fujiGain, 1.0, accuracy: 1e-9, "luma=\(luma)")
        }
    }

    func testSharedRelativeGamutScaleIsOrderIndependentAndKeepsBothCandidatesInUnitCube() {
        let input = SIMD3<Double>(0.80, 0.20, 0.40)
        let candidate = SIMD3<Double>(1.40, 0.10, 0.55)
        let reciprocal = SIMD3<Double>(0.62, -0.40, 0.28)
        let scale = ScannerTargetGrade.sharedRelativeGamutScale(
            input: input,
            candidate: candidate,
            reciprocalCandidate: reciprocal
        )
        let reversed = ScannerTargetGrade.sharedRelativeGamutScale(
            input: input,
            candidate: reciprocal,
            reciprocalCandidate: candidate
        )
        XCTAssertEqual(scale, reversed, accuracy: 1e-12)
        XCTAssertGreaterThan(scale, 0.0)
        XCTAssertLessThan(scale, 1.0, "fixture가 실제 gamut attenuation을 요구해야 한다")

        for output in [
            input + (candidate - input) * scale,
            input + (reciprocal - input) * scale,
        ] {
            for channel in 0..<3 {
                XCTAssertGreaterThanOrEqual(output[channel], -1e-12)
                XCTAssertLessThanOrEqual(output[channel], 1.0 + 1e-12)
            }
        }
    }

    func testReciprocalCubeUsesOneSharedGamutAttenuationBeforeEncoding() {
        let tone = designIdentityTone()
        let positive = ScannerTargetGrade.Signature(
            tone: tone,
            neutralBins: [ScannerTargetGrade.NeutralBin(luma: 0.60, a: 4.0, b: 0.0)],
            hueAnchors: []
        )
        let negative = ScannerTargetGrade.Signature(
            tone: tone,
            neutralBins: [ScannerTargetGrade.NeutralBin(luma: 0.60, a: -4.0, b: 0.0)],
            hueAnchors: []
        )
        let input = SIMD3<Double>(1.0, 0.5, 0.5)
        let luma = 0.2126 * input.x + 0.7152 * input.y + 0.0722 * input.z
        let lab = ScannerTargetGrade.srgbToLab(r: input.x, g: input.y, b: input.z)
        let taper = ScannerTargetGrade.smoothstep(0.03, 0.10, luma)
            * (1.0 - ScannerTargetGrade.smoothstep(0.90, 0.97, luma))
        let positiveRGB = ScannerTargetGrade.labToExtendedSRGB(
            l: lab.l, a: lab.a + 4.0 * taper, b: lab.b
        )
        let negativeRGB = ScannerTargetGrade.labToExtendedSRGB(
            l: lab.l, a: lab.a - 4.0 * taper, b: lab.b
        )
        let positiveCandidate = SIMD3(positiveRGB.r, positiveRGB.g, positiveRGB.b)
        let negativeCandidate = SIMD3(negativeRGB.r, negativeRGB.g, negativeRGB.b)
        let scale = ScannerTargetGrade.sharedRelativeGamutScale(
            input: input,
            candidate: positiveCandidate,
            reciprocalCandidate: negativeCandidate
        )
        XCTAssertLessThan(scale, 1.0, "한 방향의 red excursion이 unit gamut을 넘어야 한다")

        let dimension = 9
        let positiveCube = ScannerTargetGrade.makeCubeData(
            signature: positive, dimension: dimension
        ).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let negativeCube = ScannerTargetGrade.makeCubeData(
            signature: negative, dimension: dimension
        ).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let ri = dimension - 1
        let gi = (dimension - 1) / 2
        let bi = (dimension - 1) / 2
        let offset = ((bi * dimension + gi) * dimension + ri) * 4
        let expectedPositive = input + (positiveCandidate - input) * scale
        let expectedNegative = input + (negativeCandidate - input) * scale
        for channel in 0..<3 {
            XCTAssertEqual(
                Double(positiveCube[offset + channel]),
                expectedPositive[channel],
                accuracy: 1e-5,
                "정방향 cube가 reciprocal과 공유한 scale을 써야 한다"
            )
            XCTAssertEqual(
                Double(negativeCube[offset + channel]),
                expectedNegative[channel],
                accuracy: 1e-5,
                "reciprocal cube도 같은 scale을 써야 한다"
            )
        }
    }

    func testBoundedRelativeGradeUsesSRGBCubeDomainForDarkTaper() {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let source: [Float] = [0.01, 0.01, 0.01, 1.0]
        let image = CIImage(
            bitmapData: Data(bytes: source, count: source.count * MemoryLayout<Float>.size),
            bytesPerRow: 4 * MemoryLayout<Float>.size,
            size: CGSize(width: 1, height: 1),
            format: .RGBAf,
            colorSpace: linear
        )
        let signature = ScannerTargetGrade.Signature(
            tone: designIdentityTone().map { min($0 + 0.08, 0.998) },
            neutralBins: [],
            hueAnchors: []
        )
        let direct = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": ScannerTargetGrade.cubeDimension,
            "inputCubeData": ScannerTargetGrade.cubeData(for: signature),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
        ]).cropped(to: image.extent)
        let bounded = ScannerTargetGrade.apply(
            to: image,
            signature: signature,
            target: .noritsu
        )
        let originalPixels = renderSRGB8(image, width: 1, height: 1)
        let directPixels = renderSRGB8(direct, width: 1, height: 1)
        let boundedPixels = renderSRGB8(bounded, width: 1, height: 1)
        XCTAssertGreaterThan(
            abs(Int(directPixels[0]) - Int(originalPixels[0])),
            8,
            "fixture가 실제 LUT 이동을 만들어야 한다"
        )
        for channel in 0..<3 {
            XCTAssertEqual(
                boundedPixels[channel],
                directPixels[channel],
                accuracy: 1,
                "linear 0.01은 sRGB 약 0.10이므로 0.02 하단 taper 밖에서 LUT가 전부 적용되어야 한다"
            )
        }
    }

    // MARK: 순수 함수 (보간/커브)

    func testMonotoneCubicPassesThroughKnotsAndStaysMonotone() {
        let xs: [Double] = [0.0, 0.1, 0.35, 0.74, 0.95, 1.0]
        let ys: [Double] = [0.0, 0.05, 0.30, 0.60, 0.93, 1.0]
        let curve = MonotoneCubic(xs: xs, ys: ys)
        for (x, y) in zip(xs, ys) {
            XCTAssertEqual(curve.value(x), y, accuracy: 1e-9, "PCHIP 은 knot 을 정확히 통과해야 한다")
        }
        var previous = -1.0
        for i in 0...1000 {
            let v = curve.value(Double(i) / 1000.0)
            XCTAssertGreaterThanOrEqual(v + 1e-12, previous, "단조성이 깨지면 안 된다")
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
            previous = v
        }
    }

    func testHueResponseInterpolationWrapsAroundCircle() {
        let anchors = [
            ScannerTargetGrade.HueAnchor(hueDegrees: 60, chromaGain: 0.9, rotateDegrees: -2),
            ScannerTargetGrade.HueAnchor(hueDegrees: 240, chromaGain: 1.1, rotateDegrees: 2),
        ]
        // 앵커 위 정확값.
        XCTAssertEqual(ScannerTargetGrade.hueResponse(at: 60, anchors: anchors).gain, 0.9, accuracy: 1e-9)
        XCTAssertEqual(ScannerTargetGrade.hueResponse(at: 240, anchors: anchors).gain, 1.1, accuracy: 1e-9)
        // gain은 역수 대칭을 보존하도록 log-domain에서 보간한다.
        let geometricMid = sqrt(0.9 * 1.1)
        XCTAssertEqual(
            ScannerTargetGrade.hueResponse(at: 150, anchors: anchors).gain,
            geometricMid,
            accuracy: 1e-9
        )
        // wrap 구간(240→60+360): 330°도 log-domain 중간.
        XCTAssertEqual(
            ScannerTargetGrade.hueResponse(at: 330, anchors: anchors).gain,
            geometricMid,
            accuracy: 1e-9
        )
        // wrap 반대편(0° = 240 에서 120° 지점, 전체 180° 구간).
        XCTAssertEqual(
            ScannerTargetGrade.hueResponse(at: 0, anchors: anchors).gain,
            exp(log(1.1) + (log(0.9) - log(1.1)) * (120.0 / 180.0)),
            accuracy: 1e-9
        )
    }

    func testNeutralDriftInterpolatesBetweenBins() {
        let bins = [
            ScannerTargetGrade.NeutralBin(luma: 0.25, a: 1.0, b: -1.0),
            ScannerTargetGrade.NeutralBin(luma: 0.75, a: 3.0, b: 1.0),
        ]
        let mid = ScannerTargetGrade.neutralDrift(at: 0.5, bins: bins)
        XCTAssertEqual(mid.a, 2.0, accuracy: 1e-9)
        XCTAssertEqual(mid.b, 0.0, accuracy: 1e-9)
        // 범위 밖은 가장 가까운 bin 값(끝점 테이퍼는 별도).
        XCTAssertEqual(ScannerTargetGrade.neutralDrift(at: 0.0, bins: bins).a, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ScannerTargetGrade.neutralDrift(at: 1.0, bins: bins).a, 3.0, accuracy: 1e-9)
    }

    // MARK: 렌더 헬퍼

    private func clampByte(_ v: Double) -> UInt8 {
        UInt8(min(255, max(0, Int(v * 255.0 + 0.5))))
    }

    private func makeLinearImage(width: Int, height: Int,
                                 pixel: (Int, Int) -> (Double, Double, Double)) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let (r, g, b) = pixel(x, y)
                bytes[i] = clampByte(r); bytes[i + 1] = clampByte(g); bytes[i + 2] = clampByte(b)
                bytes[i + 3] = 255
            }
        }
        var mutable = bytes
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    /// 엔진 export 경로와 동일: working linear → 출력 sRGB(감마 인코딩).
    private func renderSRGB8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var out = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &out, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return out
    }

    private func designIdentityTone() -> [Double] {
        ScannerTargetGrade.designPercentiles.map { ScannerTargetGrade.srgbEncode($0) }
    }

    // MARK: 감마 도메인 정합 (핵심 수정 검증)

    /// 실측 percentile(sRGB 감마 도메인 값)이 설계 앵커 입력에서 최종 sRGB 출력에 **그대로**
    /// 나타나야 한다. 과거 구현(linear 도메인 적용)에서는 p50 0.595 가 출력 0.80 으로 떴다.
    func testToneSignatureLandsExactlyInOutputGammaDomain() {
        var tone = designIdentityTone()
        tone[2] = 0.133   // p10 (SP-3000 Ektar 실측)
        tone[4] = 0.595   // p50
        tone[6] = 0.852   // p90
        // 단조 유지를 위해 인접 앵커도 실측 근사값으로.
        tone[0] = 0.038; tone[1] = 0.077; tone[3] = 0.310
        tone[5] = 0.753; tone[7] = 0.914; tone[8] = 0.957
        let sig = ScannerTargetGrade.Signature(
            tone: tone, neutralBins: [], hueAnchors: [])

        // 설계 앵커 입력: linear 작업값 q (엔진 작업공간 그대로).
        let width = 3, height = 1
        let anchors = [0.10, 0.50, 0.90]
        let img = makeLinearImage(width: width, height: height) { x, _ in
            let v = anchors[x]
            return (v, v, v)
        }
        // 채도/vibrance 는 중립 회색에 영향이 없으므로 sp3000 타겟 그대로 검증 가능.
        let out = renderSRGB8(
            ScannerTargetGrade.apply(to: img, signature: sig, target: .sp3000),
            width: width, height: height)
        let expected = [0.133, 0.595, 0.852]
        for x in 0..<width {
            let got = Double(out[x * 4]) / 255.0
            XCTAssertEqual(got, expected[x], accuracy: 0.02,
                "설계 앵커 \(anchors[x]) → 실측 \(expected[x]) 이 출력 감마 도메인에 나타나야 한다. got=\(got)")
        }
    }

    func testToneOnlyChangesLightnessWithoutHiddenLabChromaShift() {
        let tone = ScannerTargetGrade.designToneXs.map { pow($0, 0.72) }
        let gradedSignature = ScannerTargetGrade.Signature(
            tone: tone,
            neutralBins: [],
            hueAnchors: []
        )
        let identitySignature = ScannerTargetGrade.Signature(
            tone: ScannerTargetGrade.designToneXs,
            neutralBins: [],
            hueAnchors: []
        )
        let input = makeLinearImage(width: 1, height: 1) { _, _ in (0.12, 0.32, 0.58) }
        let identity = renderSRGB8(
            ScannerTargetGrade.apply(to: input, signature: identitySignature, target: .main),
            width: 1,
            height: 1
        )
        let graded = renderSRGB8(
            ScannerTargetGrade.apply(to: input, signature: gradedSignature, target: .main),
            width: 1,
            height: 1
        )
        func lab(_ bytes: [UInt8]) -> (l: Double, a: Double, b: Double) {
            ScannerTargetGrade.srgbToLab(
                r: Double(bytes[0]) / 255.0,
                g: Double(bytes[1]) / 255.0,
                b: Double(bytes[2]) / 255.0
            )
        }
        let before = lab(identity)
        let after = lab(graded)
        XCTAssertGreaterThan(abs(after.l - before.l), 2.0, "fixture가 실제 tone 이동을 만들어야 한다")
        XCTAssertEqual(after.a, before.a, accuracy: 1.25, "tone-only가 Lab a*를 바꾸면 안 된다")
        XCTAssertEqual(after.b, before.b, accuracy: 1.25, "tone-only가 Lab b*를 바꾸면 안 된다")
    }

    // MARK: 중립축 드리프트 / hue 시그니처

    func testNeutralDriftShiftsMidGrayAndPreservesEndpoints() {
        let sig = ScannerTargetGrade.Signature(
            tone: designIdentityTone(),
            neutralBins: [ScannerTargetGrade.NeutralBin(luma: 0.5, a: 4.0, b: 0.0)],
            hueAnchors: [])
        let width = 3, height = 1
        let img = makeLinearImage(width: width, height: height) { x, _ in
            let v = [0.0, 0.5, 1.0][x]
            return (v, v, v)
        }
        // main 클래스(채도 1.0)로 그레이드 자체만 측정.
        let out = renderSRGB8(
            ScannerTargetGrade.apply(to: img, signature: sig, target: .main),
            width: width, height: height)
        // 순흑/순백은 중립 유지(테이퍼 + 커브 끝점 고정).
        XCTAssertLessThan(Int(out[0]), 6)
        XCTAssertLessThan(abs(Int(out[0]) - Int(out[2])), 3, "순흑 중립")
        XCTAssertGreaterThan(Int(out[8]), 249)
        XCTAssertLessThan(abs(Int(out[8]) - Int(out[10])), 3, "순백 중립")
        // 미드 그레이는 a*+4 방향(적자색: R↑, G↓)으로 이동.
        let r = Double(out[4]), g = Double(out[5]), b = Double(out[6])
        XCTAssertGreaterThan(r - g, 4.0, "Lab a*+4 드리프트가 미드에 이식되어야 한다. R=\(r) G=\(g) B=\(b)")
        // 기대값 정밀 비교: 그레이드의 Lab 변환으로 직접 계산한 값과 일치해야 한다.
        let gamma = ScannerTargetGrade.srgbEncode(0.5)
        let lab = ScannerTargetGrade.srgbToLab(r: gamma, g: gamma, b: gamma)
        let taper = ScannerTargetGrade.smoothstep(0.03, 0.10, gamma)
            * (1.0 - ScannerTargetGrade.smoothstep(0.90, 0.97, gamma))
        let expected = ScannerTargetGrade.labToSRGB(l: lab.l, a: lab.a + 4.0 * taper, b: lab.b)
        XCTAssertEqual(r / 255.0, expected.r, accuracy: 0.02)
        XCTAssertEqual(g / 255.0, expected.g, accuracy: 0.02)
        XCTAssertEqual(b / 255.0, expected.b, accuracy: 0.02)
    }

    func testHueSignatureScalesChromaSelectively() {
        // 시안-블루(≈240°) 채도 ×1.15, 옐로(≈100°) ×0.88 — SP-3000 실측 방향의 시그니처.
        let sig = ScannerTargetGrade.Signature(
            tone: designIdentityTone(),
            neutralBins: [],
            hueAnchors: [
                ScannerTargetGrade.HueAnchor(hueDegrees: 100, chromaGain: 0.88, rotateDegrees: 0),
                ScannerTargetGrade.HueAnchor(hueDegrees: 240, chromaGain: 1.15, rotateDegrees: 0),
            ])
        let neutral = ScannerTargetGrade.Signature(
            tone: designIdentityTone(), neutralBins: [], hueAnchors: [])

        let width = 2, height = 1
        // linear 픽셀: 파랑 계열 / 노랑 계열.
        let img = makeLinearImage(width: width, height: height) { x, _ in
            x == 0 ? (0.10, 0.25, 0.60) : (0.60, 0.45, 0.08)
        }
        func chroma(_ px: [UInt8], _ x: Int) -> Double {
            let lab = ScannerTargetGrade.srgbToLab(
                r: Double(px[x * 4]) / 255.0,
                g: Double(px[x * 4 + 1]) / 255.0,
                b: Double(px[x * 4 + 2]) / 255.0)
            return (lab.a * lab.a + lab.b * lab.b).squareRoot()
        }
        let graded = renderSRGB8(ScannerTargetGrade.apply(to: img, signature: sig, target: .main),
                                 width: width, height: height)
        let base = renderSRGB8(ScannerTargetGrade.apply(to: img, signature: neutral, target: .main),
                               width: width, height: height)
        XCTAssertGreaterThan(chroma(graded, 0), chroma(base, 0) * 1.05,
            "파랑 채도는 시그니처대로 증가해야 한다")
        XCTAssertLessThan(chroma(graded, 1), chroma(base, 1) * 0.97,
            "노랑 채도는 시그니처대로 감소해야 한다")
    }

    // MARK: 파이프라인 분기

    /// 가장자리 = 베이스, 내부 = 중립 밀도 램프 합성 네거티브.
    private func makeSyntheticNegative(width: Int, height: Int, base: SIMD3<Double>) -> CIImage {
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        return makeLinearImage(width: width, height: height) { x, y in
            let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
            // 풀레인지 장면(딥 섀도~딥 하이라이트): 계조 폭이 톤 전이의 지지(0.66) 안쪽으로
            // 좁으면 sceneToneAnchor 가 노출 개성을 앵커해 실측 경향 계약(SP 미드 > NOR)을
            // 검증할 수 없다 — 계약은 풀레인지 장면의 것이다(2026-07-23 rebate 판별 도입 이후).
            let density = isBorder ? 0.0 : (0.12 + 2.2 * Double(x) / Double(width - 1))
            let atten = pow(10.0, -density)
            return (base.x * atten, base.y * atten, base.z * atten)
        }
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0.0
        for i in stride(from: 0, to: a.count, by: 4) {
            sum += abs(Double(a[i]) - Double(b[i]))
                + abs(Double(a[i + 1]) - Double(b[i + 1]))
                + abs(Double(a[i + 2]) - Double(b[i + 2]))
        }
        return sum / Double(a.count / 4)
    }

    private func developed(
        target: DevelopTarget,
        filmType: FilmType = .colorNegative,
        input: CIImage,
        base: FilmBase?,
        width: Int,
        height: Int,
        scannerProfileID: String? = nil
    ) -> [UInt8] {
        var params = DevelopParameters()
        params.filmType = filmType
        params.developTarget = target
        params.scannerProfileID = scannerProfileID
        return renderSRGB8(
            ChromabaseEngine().develop(image: input, base: base, params: params),
            width: width, height: height)
    }

    func testEmulationTargetsDivergeFromMainAndEachOtherDeterministically() {
        let width = 96, height = 48
        let base = SIMD3<Double>(0.82, 0.55, 0.34)
        let input = makeSyntheticNegative(width: width, height: height, base: base)
        let fb = FilmBase(rgb: base, source: .border)

        let main = developed(target: .main, input: input, base: fb, width: width, height: height)
        let nor1 = developed(target: .noritsu, input: input, base: fb, width: width, height: height)
        let nor2 = developed(target: .noritsu, input: input, base: fb, width: width, height: height)
        let sp = developed(target: .sp3000, input: input, base: fb, width: width, height: height)

        XCTAssertEqual(nor1, nor2, "독자 타겟은 결정적이어야 한다")

        XCTAssertGreaterThan(meanAbsDiff(main, nor1), 1.0,
            "NORITSU HS-1800 은 main 베이스와 달라야 한다(독자 베이스)")
        XCTAssertGreaterThan(meanAbsDiff(main, sp), 1.0,
            "FUJI SP-3000 은 main 베이스와 달라야 한다(독자 베이스)")
        XCTAssertGreaterThan(meanAbsDiff(nor1, sp), 1.0,
            "두 스캐너 타겟은 서로 달라야 한다(실측 시그니처 차이)")
    }

    /// 평탄/흐린 장면(developed 계조가 좁은 상부 대역에 몰림)은 스캐너 톤 전이의 지지
    /// (캘리브레이션 corpus p5~p95 spread≈0.70) 밖 — 노출 앵커가 장면 median 을 보존해
    /// FUJI 히스토그램 우측 밀림(≈1스탑 과노출)을 막아야 한다. 색 개성은 유지된다.
    func testFlatSceneKeepsScannerTargetExposureAnchoredToMain() {
        let width = 96, height = 48
        let base = SIMD3<Double>(0.82, 0.55, 0.34)
        // 경계 5% — 실사용 프레임(크롭 후)처럼 rebate 가 앵커 샘플러 인셋(6%) 안에 들어온다.
        let bx = Int(Double(width) * 0.05), by = Int(Double(height) * 0.05)
        // 흐린 풍경 네거티브: 밀도 0.6~1.5(밝은 하늘/미드만, 깊은 섀도 없음).
        let flat = makeLinearImage(width: width, height: height) { x, y in
            let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
            let density = isBorder ? 0.0 : (0.6 + 0.9 * Double(x) / Double(width - 1))
            let atten = pow(10.0, -density)
            return (base.x * atten, base.y * atten, base.z * atten)
        }
        let fb = FilmBase(rgb: base, source: .border)
        let main = developed(target: .main, input: flat, base: fb, width: width, height: height)
        let fuji = developed(target: .sp3000, input: flat, base: fb, width: width, height: height)
        let nor = developed(target: .noritsu, input: flat, base: fb, width: width, height: height)

        let mainL = interiorLumaPercentiles(main, width: width, height: height)
        let fujiL = interiorLumaPercentiles(fuji, width: width, height: height)
        let norL = interiorLumaPercentiles(nor, width: width, height: height)

        XCTAssertLessThanOrEqual(abs(fujiL.p50 - mainL.p50), 6.0,
            "평탄 장면에서 FUJI median 노출은 MAIN 에 앵커돼야 한다")
        XCTAssertLessThanOrEqual(fujiL.p95, mainL.p95 + 6.0,
            "평탄 장면에서 FUJI 히스토그램이 우측으로 밀리면 안 된다")
        XCTAssertLessThanOrEqual(abs(norL.p50 - mainL.p50), 6.0,
            "평탄 장면에서 NORITSU median 노출도 앵커돼야 한다")
        XCTAssertGreaterThan(meanAbsDiff(fuji, main), 0.8,
            "노출 앵커가 FUJI 색 개성까지 지우면 안 된다")
    }

    /// NORITSU 문서 질감(기본 샤픈 — "끌 수 없다"가 문서화된 시그니처): 실제 그레인을
    /// crisp 하게 만들고, FUJI/MAIN 은 소프트하게 유지된다. 흑백 중립도 깨지 않는다.
    func testNoritsuDocumentedTextureCrispensExistingGrain() {
        let width = 96, height = 48
        let base = SIMD3<Double>(0.82, 0.55, 0.34)
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        func grainNegative(base: SIMD3<Double>) -> CIImage {
            makeLinearImage(width: width, height: height) { x, y in
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                let h = UInt32(truncatingIfNeeded: (x &* 73_856_093) ^ (y &* 19_349_663))
                let jitter = (Double(h % 1000) / 1000.0 - 0.5) * 0.12
                let density = isBorder ? 0.0
                    : max(0.05, 0.5 + 1.0 * Double(x) / Double(width - 1) + jitter)
                let atten = pow(10.0, -density)
                return (base.x * atten, base.y * atten, base.z * atten)
            }
        }
        let input = grainNegative(base: base)
        let fb = FilmBase(rgb: base, source: .border)
        let main = developed(target: .main, input: input, base: fb, width: width, height: height)
        let nor = developed(target: .noritsu, input: input, base: fb, width: width, height: height)
        let fuji = developed(target: .sp3000, input: input, base: fb, width: width, height: height)

        let hfMain = interiorHFEnergy(main, width: width, height: height)
        let hfNor = interiorHFEnergy(nor, width: width, height: height)
        let hfFuji = interiorHFEnergy(fuji, width: width, height: height)
        XCTAssertGreaterThan(hfNor, hfMain * 1.10, "NORITSU 는 그레인이 crisp 해야 한다(샤픈)")
        XCTAssertGreaterThan(hfNor, hfFuji * 1.05, "FUJI 는 NORITSU 보다 소프트해야 한다")

        // 흑백: luminance USM 이라 중립(R=G=B)이 유지돼야 한다.
        let bwBase = SIMD3<Double>(repeating: 0.80)
        let bwNor = developed(target: .noritsu, filmType: .bwNegative,
                              input: grainNegative(base: bwBase), base: FilmBase(rgb: bwBase, source: .border),
                              width: width, height: height)
        var maxSpread = 0
        for i in stride(from: 0, to: bwNor.count, by: 4) {
            let spread = Int(max(max(bwNor[i], bwNor[i + 1]), bwNor[i + 2]))
                - Int(min(min(bwNor[i], bwNor[i + 1]), bwNor[i + 2]))
            maxSpread = max(maxSpread, spread)
        }
        XCTAssertLessThanOrEqual(maxSpread, 1, "NORITSU 샤픈이 흑백 중립을 깨면 안 된다")
    }

    private func interiorLumaPercentiles(
        _ px: [UInt8], width: Int, height: Int
    ) -> (p50: Double, p95: Double) {
        let ix = Int(Double(width) * 0.10), iy = Int(Double(height) * 0.10)
        var lumas: [Double] = []
        for y in iy..<(height - iy) {
            for x in ix..<(width - ix) {
                let i = (y * width + x) * 4
                lumas.append(0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1])
                    + 0.0722 * Double(px[i + 2]))
            }
        }
        lumas.sort()
        func pct(_ f: Double) -> Double {
            lumas[max(0, min(lumas.count - 1, Int(Double(lumas.count - 1) * f)))]
        }
        return (pct(0.5), pct(0.95))
    }

    private func interiorHFEnergy(_ px: [UInt8], width: Int, height: Int) -> Double {
        let ix = Int(Double(width) * 0.10), iy = Int(Double(height) * 0.10)
        var sum = 0.0
        var count = 0
        for y in iy..<(height - iy) {
            for x in ix..<(width - ix - 1) {
                let i = (y * width + x) * 4
                let j = i + 4
                let a = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
                let b = 0.2126 * Double(px[j]) + 0.7152 * Double(px[j + 1]) + 0.0722 * Double(px[j + 2])
                sum += abs(a - b)
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    func testDocumentedCharacterMakesAllFilmTypesDistinctFromMainAndKeepsBWNeutral() {
        let width = 96, height = 48
        let colorNegativeBase = SIMD3<Double>(0.82, 0.55, 0.34)
        let bwNegativeBase = SIMD3<Double>(repeating: 0.80)
        let fixtures: [(FilmType, CIImage, FilmBase?)] = [
            (
                .colorNegative,
                makeSyntheticNegative(width: width, height: height, base: colorNegativeBase),
                FilmBase(rgb: colorNegativeBase, source: .border)
            ),
            (
                .colorPositive,
                makeLinearImage(width: width, height: height) { x, y in
                    let fx = Double(x) / Double(width - 1)
                    let fy = Double(y) / Double(height - 1)
                    return (0.05 + 0.82 * fx, 0.08 + 0.76 * fy, 0.10 + 0.72 * (1.0 - fx))
                },
                nil
            ),
            (
                .bwNegative,
                makeSyntheticNegative(width: width, height: height, base: bwNegativeBase),
                FilmBase(rgb: bwNegativeBase, source: .border)
            ),
            (
                .bwPositive,
                makeLinearImage(width: width, height: height) { x, _ in
                    let value = 0.03 + 0.94 * Double(x) / Double(width - 1)
                    return (value, value, value)
                },
                nil
            ),
        ]

        for (filmType, input, base) in fixtures {
            let main = developed(
                target: .main,
                filmType: filmType,
                input: input,
                base: base,
                width: width,
                height: height
            )
            let emulations: [DevelopTarget] = [.noritsu, .sp3000, .f135, .hr]
            var outputs: [DevelopTarget: [UInt8]] = [:]
            for target in emulations {
                outputs[target] = developed(
                    target: target,
                    filmType: filmType,
                    input: input,
                    base: base,
                    width: width,
                    height: height
                )
            }

            // 문서 개성은 4개 조합(컬러/흑백 × 슬라이드/네거티브) 전부에 적용된다 — 각 스캐너가
            // MAIN 과, 그리고 서로 구별돼야 한다. 포지티브(슬라이드)는 감쇠 적용이라 임계값이 낮다.
            let threshold = (filmType == .colorPositive || filmType == .bwPositive) ? 0.5 : 1.0
            for target in emulations {
                XCTAssertGreaterThan(meanAbsDiff(main, outputs[target]!), threshold,
                                     "\(filmType) \(target.displayName)가 MAIN과 같음")
            }
            for (index, lhs) in emulations.enumerated() {
                for rhs in emulations.dropFirst(index + 1) {
                    XCTAssertGreaterThan(
                        meanAbsDiff(outputs[lhs]!, outputs[rhs]!), threshold,
                        "\(filmType) \(lhs.displayName)/\(rhs.displayName) 두 타겟이 같음")
                }
            }

            // 흑백: 모든 실기 타겟이 중립이어야 한다. 장치별 흑백 틴트는 번들 프로파일에
            // 측정값이 없으므로 문헌 방향만으로 고정 색을 만들지 않는다(하드코딩 금지 계약
            // — 과거 FUJI 웜 틴트 상수는 이 이유로 제거됨).
            func maxSpread(_ pixels: [UInt8]) -> Int {
                var maxSpread = 0
                for i in stride(from: 0, to: pixels.count, by: 4) {
                    let spread = Int(max(max(pixels[i], pixels[i + 1]), pixels[i + 2]))
                        - Int(min(min(pixels[i], pixels[i + 1]), pixels[i + 2]))
                    maxSpread = max(maxSpread, spread)
                }
                return maxSpread
            }
            if filmType == .bwPositive || filmType == .bwNegative {
                for target in emulations {
                    XCTAssertLessThanOrEqual(maxSpread(outputs[target]!), 1,
                                             "\(filmType) \(target.displayName) 중립 위반")
                }
            }
        }
    }

    func testUnsupportedPositiveScannerTargetIgnoresStaleScannerProfileID() throws {
        let width = 96, height = 48
        let input = makeLinearImage(width: width, height: height) { x, y in
            let fx = Double(x) / Double(width - 1)
            let fy = Double(y) / Double(height - 1)
            return (0.05 + 0.82 * fx, 0.08 + 0.76 * fy, 0.10 + 0.72 * (1.0 - fx))
        }
        let staleProfileID = try XCTUnwrap(
            ScannerProfileRegistry.loadAll().first {
                $0.scanner == "NORITSU" && $0.kind == "color slide"
            }?.id
        )
        let main = developed(
            target: .main,
            filmType: .colorPositive,
            input: input,
            base: nil,
            width: width,
            height: height
        )
        for target in [DevelopTarget.noritsu, .sp3000] {
            let withStale = developed(
                target: target,
                filmType: .colorPositive,
                input: input,
                base: nil,
                width: width,
                height: height,
                scannerProfileID: staleProfileID
            )
            let withoutID = developed(
                target: target,
                filmType: .colorPositive,
                input: input,
                base: nil,
                width: width,
                height: height
            )
            // 슬라이드 pair 가 0개라 stale scannerProfileID 는 실측 차분을 만들지 않는다 →
            // profileID 유무와 무관하게 문서 개성만 적용돼 결과가 동일해야 한다(stale 무시).
            XCTAssertEqual(
                withStale,
                withoutID,
                "paired positive evidence가 없으면 stale scannerProfileID 는 무시돼야 한다"
            )
            // 다만 포지티브도 문서 개성으로 MAIN 과는 구별된다.
            XCTAssertGreaterThan(meanAbsDiff(main, withStale), 0.5,
                "포지티브도 문서 개성으로 MAIN 과 구별돼야 한다")
        }
    }

    /// 실측 경향 이식 확인: 같은 입력에서 SP-3000 의 미드톤이 NORITSU 보다 밝아야 한다
    /// (실측 스캐너 공통 p50: SP > NOR — 같은 롤 쌍 포함 REAL 데이터).
    func testSP3000MidtoneBrighterThanNoritsuAsMeasured() {
        let width = 96, height = 48
        let base = SIMD3<Double>(0.82, 0.55, 0.34)
        let input = makeSyntheticNegative(width: width, height: height, base: base)
        let fb = FilmBase(rgb: base, source: .border)
        let nor = developed(target: .noritsu, input: input, base: fb, width: width, height: height)
        let sp = developed(target: .sp3000, input: input, base: fb, width: width, height: height)

        // 미드톤 대역(전체 luma 의 중간 1/3 구간) 평균 비교.
        func midtoneMean(_ px: [UInt8]) -> Double {
            var lumas: [Double] = []
            for i in stride(from: 0, to: px.count, by: 4) {
                lumas.append(0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2]))
            }
            let sorted = lumas.sorted()
            let third = sorted.count / 3
            let mid = sorted[third..<(2 * third)]
            return mid.reduce(0, +) / Double(mid.count)
        }
        let norMid = midtoneMean(nor)
        let spMid = midtoneMean(sp)
        XCTAssertGreaterThan(spMid, norMid + 2.0,
            "SP-3000 미드톤이 실측대로 더 밝아야 한다. sp=\(spMid) nor=\(norMid)")
    }

    // MARK: 포지티브(슬라이드/흑백 양화) 시그니처

    private func makeStat(_ value: Double) -> ScannerProfileStat {
        ScannerProfileStat(count: 30, mean: value, median: value,
                           p10: value, p90: value, min: value, max: value)
    }

    private func makeSlideProfile(
        scanner: String,
        filmKey: String,
        imageCount: Int,
        tone: [Double],
        neutralBins: [ScannerProfileNeutralBin] = [],
        sharpness: Double = 0.40,
        rolls: [String] = ["roll-01"]
    ) -> ScannerProfile {
        var toneStats: [String: ScannerProfileStat] = [:]
        for (index, key) in ScannerTargetGrade.toneKeys.enumerated() {
            toneStats[key] = makeStat(tone[index])
        }
        return ScannerProfile(
            schemaVersion: 2,
            id: "\(scanner)-slide-\(filmKey)",
            displayName: "\(scanner) slide \(filmKey)",
            scanner: scanner,
            kind: "color slide",
            filmKey: filmKey,
            validationStatus: .realOnly,
            rollCount: rolls.count,
            imageCount: imageCount,
            singleRollLimited: rolls.count == 1,
            sourceProfiles: rolls.map { "profiles/\(scanner)/color slide/\($0)/profile.json" },
            tone: toneStats,
            color: [:],
            neutralAxis: [:],
            neutralAxisBins: neutralBins,
            hueResponse: nil,
            texture: ["texture_sharpness_p95": makeStat(sharpness)],
            sceneBuckets: [],
            coverageCandidates: [],
            profileHash: "sha256:test"
        )
    }

    /// 같은 필름 쌍의 톤/중립축 차이가 중점 기준으로 대칭 분배되어야 한다(상대 이식).
    func testPositiveSignatureSplitsPairedSlideDifferenceSymmetrically() {
        let norTone = [0.040, 0.060, 0.080, 0.150, 0.430, 0.690, 0.810, 0.860, 0.910]
        let spTone = [0.030, 0.050, 0.082, 0.220, 0.520, 0.730, 0.830, 0.862, 0.885]
        let norBin = ScannerProfileNeutralBin(lumaCenter: 0.45, coveragePct: 0.5, labA: -2.0, labB: 1.6)
        let spBin = ScannerProfileNeutralBin(lumaCenter: 0.45, coveragePct: 0.5, labA: 3.0, labB: -2.0)
        let profiles = [
            makeSlideProfile(scanner: "NORITSU", filmKey: "test-100d", imageCount: 40,
                             tone: norTone, neutralBins: [norBin], sharpness: 0.43),
            makeSlideProfile(scanner: "SP-3000", filmKey: "test-100d", imageCount: 37,
                             tone: spTone, neutralBins: [spBin], sharpness: 0.27),
        ]
        guard let sp = ScannerTargetGrade.positiveSignature(scanner: "SP-3000", profiles: profiles),
              let nor = ScannerTargetGrade.positiveSignature(scanner: "NORITSU", profiles: profiles) else {
            return XCTFail("포지티브 시그니처 생성 실패")
        }
        for i in 0..<ScannerTargetGrade.toneKeys.count {
            let midpoint = (norTone[i] + spTone[i]) / 2
            XCTAssertEqual(sp.toneXs[i], midpoint, accuracy: 1e-9, "knot 위치는 두 실기 중점")
            XCTAssertEqual(nor.toneXs[i], midpoint, accuracy: 1e-9)
            XCTAssertEqual(sp.tone[i], spTone[i], accuracy: 1e-9, "단일 쌍이면 자기 실측값 복원")
            XCTAssertEqual(nor.tone[i], norTone[i], accuracy: 1e-9)
        }
        // 중립축: (자기 − 상대)/2 — 필름/장면 캐스트는 상쇄되고 스캐너 차이만 남는다.
        XCTAssertEqual(sp.neutralBins.count, 1)
        XCTAssertEqual(sp.neutralBins[0].a, 2.5, accuracy: 1e-9)
        XCTAssertEqual(sp.neutralBins[0].b, -1.8, accuracy: 1e-9)
        XCTAssertEqual(nor.neutralBins[0].a, -2.5, accuracy: 1e-9)
        XCTAssertEqual(nor.neutralBins[0].b, 1.8, accuracy: 1e-9)
    }

    /// 쌍이 없으면 nil/no-op, roll-label pair의 극단 차이는 앵커별 ±0.10으로 제한한다.
    func testPositiveSignatureNoPairIsNoOpAndPairedDeltaIsClamped() {
        // 1. 상대 스캐너 프로파일 없음 → nil.
        let lone = [makeSlideProfile(scanner: "NORITSU", filmKey: "solo", imageCount: 30,
                                     tone: [0.02, 0.05, 0.10, 0.20, 0.40, 0.60, 0.75, 0.85, 0.95])]
        XCTAssertNil(ScannerTargetGrade.positiveSignature(scanner: "NORITSU", profiles: lone),
                     "roll-label pair가 없는 슬라이드는 전체 no-op이어야 한다")

        let sameFilmDifferentRolls = [
            makeSlideProfile(scanner: "NORITSU", filmKey: "same-film", imageCount: 30,
                             tone: Array(repeating: 0.3, count: 9), rolls: ["roll-a"]),
            makeSlideProfile(scanner: "SP-3000", filmKey: "same-film", imageCount: 30,
                             tone: Array(repeating: 0.7, count: 9), rolls: ["roll-b"]),
        ]
        XCTAssertNil(ScannerTargetGrade.positiveSignature(
            scanner: "NORITSU", profiles: sameFilmDifferentRolls
        ), "filmKey만 같은 서로 다른 롤을 pair로 취급하면 안 된다")

        // 2. 극단 차이(0.5) → ±0.10 클램프.
        let flat = [Double](repeating: 0.3, count: 9).enumerated().map { $0.1 + Double($0.0) * 0.01 }
        let bright = flat.map { $0 + 0.5 }
        let profiles = [
            makeSlideProfile(scanner: "NORITSU", filmKey: "x", imageCount: 30, tone: flat),
            makeSlideProfile(scanner: "SP-3000", filmKey: "x", imageCount: 30, tone: bright),
        ]
        guard let sp = ScannerTargetGrade.positiveSignature(scanner: "SP-3000", profiles: profiles) else {
            return XCTFail("클램프 시그니처 생성 실패")
        }
        for i in 0..<9 {
            XCTAssertEqual(sp.tone[i] - sp.toneXs[i], ScannerTargetGrade.positiveToneDeltaLimit,
                           accuracy: 1e-9, "델타는 ±\(ScannerTargetGrade.positiveToneDeltaLimit) 클램프")
        }
    }

    /// resolveSignature의 필름 타입 분기: 번들 포지티브는 roll-label pair가 없어 nil이며,
    /// 네거티브 pair는 흑백에서 색 성분만 제거한다.
    func testResolveSignatureFilmTypeBranches() throws {
        let all = ScannerProfileRegistry.loadAll()
        guard !all.isEmpty else { throw XCTSkip("번들 스캐너 프로파일 없음") }

        for target in [DevelopTarget.sp3000, .noritsu] {
            var slide = DevelopParameters()
            slide.developTarget = target
            slide.filmType = .colorPositive
            XCTAssertNil(ScannerTargetGrade.resolveSignature(target: target, params: slide),
                         "\(target) 번들 슬라이드는 pair가 없으므로 no-op이어야 한다")

            var bwPositive = DevelopParameters()
            bwPositive.developTarget = target
            bwPositive.filmType = .bwPositive
            XCTAssertNil(ScannerTargetGrade.resolveSignature(target: target, params: bwPositive),
                         "\(target) 흑백 양화도 pair가 없으므로 no-op이어야 한다")

            var bwNegative = DevelopParameters()
            bwNegative.developTarget = target
            bwNegative.filmType = .bwNegative
            guard let bwNegSig = ScannerTargetGrade.resolveSignature(target: target, params: bwNegative) else {
                return XCTFail("\(target) 흑백 네거 시그니처 실패")
            }
            XCTAssertTrue(bwNegSig.hueAnchors.isEmpty)
            // 흑백은 장치별 틴트 실측값이 없으므로 중립이어야 한다(문헌 방향만으로
            // 고정 색을 만들지 않는다 — 하드코딩 금지 계약).
            XCTAssertTrue(bwNegSig.neutralBins.isEmpty, "\(target) 흑백은 중립이어야 한다")
        }
    }

    /// 번들의 Ektachrome 100D는 filmKey만 같고 roll-label set이 다르므로 상대 시그니처
    /// fit으로 사용할 수 없다.
    func testBundledSlideTargetsRejectFilmKeyOnlyPairing() throws {
        let all = ScannerProfileRegistry.loadAll()
        guard all.contains(where: { $0.kind == "color slide" && $0.scanner == "SP-3000" }),
              all.contains(where: { $0.kind == "color slide" && $0.scanner == "NORITSU" }) else {
            throw XCTSkip("슬라이드 번들 프로파일 부족")
        }
        XCTAssertTrue(ScannerTargetGrade.matchedProfilePairs(
            scanner: "NORITSU", kind: "color slide", profiles: all
        ).isEmpty)
        XCTAssertNil(ScannerTargetGrade.positiveSignature(scanner: "SP-3000", profiles: all))
        XCTAssertNil(ScannerTargetGrade.positiveSignature(scanner: "NORITSU", profiles: all))
    }

    // MARK: 변환 안전성

    func testGradeClampsExtremeSignatureAndKeepsEndpoints() {
        let width = 64, height = 16
        // 극단(비정상) 시그니처 — 클램프/단조 강제가 폭주를 막아야 한다.
        let extreme = ScannerTargetGrade.Signature(
            tone: [0.95, 0.01, 0.99, 0.05, 0.98, 0.02, 0.97, 0.03, 0.96],
            neutralBins: [
                ScannerTargetGrade.NeutralBin(luma: 0.3, a: 200, b: -200),
                ScannerTargetGrade.NeutralBin(luma: 0.7, a: -300, b: 300),
            ],
            hueAnchors: [
                ScannerTargetGrade.HueAnchor(hueDegrees: 0, chromaGain: 30, rotateDegrees: 500),
                ScannerTargetGrade.HueAnchor(hueDegrees: 180, chromaGain: 0.001, rotateDegrees: -500),
            ])
        // 흑→백 램프.
        let ramp = makeLinearImage(width: width, height: height) { x, _ in
            let v = Double(x) / Double(width - 1)
            return (v, v, v)
        }
        // 시그니처 클램프/단조 가드만 검증한다. 장치 설정과 paired spatial evidence가 없는
        // 로컬 대비·샤프닝·질감은 어느 스캐너 타겟에도 추가하지 않는다.
        let out = renderSRGB8(
            ScannerTargetGrade.apply(to: ramp, signature: extreme, target: .noritsu),
            width: width, height: height)
        let midY = height / 2
        // 순흑/순백 끝점 보존(±12/255) — 커브 끝점 (0,0)/(1,1) + 드리프트 테이퍼.
        let first = (midY * width + 0) * 4
        let last = (midY * width + width - 1) * 4
        XCTAssertLessThan(Int(out[first]), 12, "순흑이 크게 뜨면 안 된다")
        XCTAssertGreaterThan(Int(out[last]), 243, "순백이 크게 내려앉으면 안 된다")
        // 전 픽셀 유효 범위(클램프 동작) + NaN 없이 렌더됨.
        for i in stride(from: 0, to: out.count, by: 4) {
            XCTAssertLessThanOrEqual(out[i], 255)
        }
    }

    // MARK: 문서 기반 절대 개성 (documentedCharacter) 방향 검증

    /// 각 스캐너의 문서화된 고유 개성이 MAIN 대비 실제 방향으로 나타나는지 합성 패치로 수치 검증.
    /// (sRGB 패치 → ScannerTargetGrade.apply(target) → sRGB8 → Lab)
    func testDocumentedCharacterExpressesEachScannerSignatureDirection() {
        // sRGB 입력 패치: [mid gray, dark gray, skin(웜탄), bright-color, dark-color, light gray,
        //                  pastel-bright, sky-blue]
        let srgbPatches: [(Double, Double, Double)] = [
            (0.50, 0.50, 0.50),
            (0.28, 0.28, 0.28),
            (0.80, 0.62, 0.52),
            (0.82, 0.58, 0.32),   // 밝은 유채(luma~0.61) — FUJI 하이라이트 채도↑
            (0.28, 0.20, 0.13),   // 어두운 유채(luma~0.21) — 섀도 탈색 금지 검증
            (0.93, 0.93, 0.93),   // 밝은 그레이 — NORITSU highlight retention(리프트 금지)
            (0.90, 0.80, 0.62),   // 파스텔 명부 유채(luma~0.81) — NORITSU 파스텔 명부 뮤트
            (0.35, 0.50, 0.80),   // 스카이 블루(luma~0.49) — HR 블루 리치 검증
        ]
        let width = srgbPatches.count, height = 1
        let img = makeLinearImage(width: width, height: height) { x, _ in
            let p = srgbPatches[x]
            return (ScannerTargetGrade.srgbDecode(p.0),
                    ScannerTargetGrade.srgbDecode(p.1),
                    ScannerTargetGrade.srgbDecode(p.2))
        }
        // 문서 시그니처만 격리 적용한다(실측 차분은 별도 riding refinement 이며 그 방향은 필름별
        // 실측이라 여기서 섞으면 문서 개성의 방향 검증이 흐려진다 — 차분/발산은 다른 테스트가 검증).
        func labs(_ target: DevelopTarget) -> [(l: Double, a: Double, b: Double)] {
            let graded: CIImage
            if let doc = ScannerTargetGrade.documentedCharacter(
                target: target, filmType: .colorNegative, monochrome: false) {
                graded = ScannerTargetGrade.apply(to: img, signature: doc, target: target)
            } else {
                graded = img   // MAIN: 문서 개성 없음
            }
            let out = renderSRGB8(graded, width: width, height: height)
            return (0..<width).map { x in
                ScannerTargetGrade.srgbToLab(
                    r: Double(out[x * 4]) / 255.0,
                    g: Double(out[x * 4 + 1]) / 255.0,
                    b: Double(out[x * 4 + 2]) / 255.0
                )
            }
        }
        let main = labs(.main), nor = labs(.noritsu), fuji = labs(.sp3000)
        func de(_ a: (l: Double, a: Double, b: Double), _ b: (l: Double, a: Double, b: Double)) -> Double {
            hypot(hypot(a.l - b.l, a.a - b.a), a.b - b.b)
        }

        func chroma(_ p: (l: Double, a: Double, b: Double)) -> Double { hypot(p.a, p.b) }

        // MAIN 은 문서 개성이 없다(no-op) → 두 스캐너가 MAIN 과 지각적으로 구별돼야 한다.
        XCTAssertGreaterThan(de(fuji[0], main[0]), 1.5, "FUJI mid gray 가 MAIN 과 구별돼야")
        XCTAssertGreaterThan(de(nor[0], main[0]), 1.5, "NORITSU mid gray 가 MAIN 과 구별돼야")
        XCTAssertGreaterThan(de(fuji[0], nor[0]), 1.5, "FUJI≠NORITSU")

        // 1) 톤(실측 SP-3000 캘리브레이션): FUJI 는 미드를 밝게(L*↑) — MAIN·NORITSU 보다 밝다.
        //    NORITSU 는 미드 톤을 거의 유지(문서: 톤 충실)한다.
        XCTAssertGreaterThan(fuji[0].l, main[0].l + 1.0, "FUJI mid gray 는 밝다(미드 리프트)")
        XCTAssertGreaterThan(fuji[0].l, nor[0].l, "FUJI 미드가 NORITSU 보다 밝다")

        // 2) 그레이 온도(2026-07-23 재설계): NORITSU 미드 그레이는 웜-피치(b*↑ + a*≥),
        //    섀도 그레이는 모노크로매틱 중립(문헌: "중립 섀도, 웜 미드" — 그림자가 색으로
        //    흩어지지 않는다). FUJI 미드 b*≈0(실측)이므로 HS 가 FUJI 보다 웜 쪽이다.
        XCTAssertGreaterThan(nor[0].b, main[0].b + 1.2, "NORITSU mid gray 는 웜-피치(b*↑)")
        XCTAssertGreaterThanOrEqual(nor[0].a, main[0].a - 0.2, "NORITSU mid gray 마젠타 경향(a* 감소 금지)")
        XCTAssertGreaterThan(nor[0].b, fuji[0].b, "HS 그레이가 FUJI 보다 웜 쪽")
        XCTAssertLessThan(abs(nor[1].a - main[1].a), 0.8, "NORITSU 섀도 그레이는 중립(a*)")
        XCTAssertLessThan(abs(nor[1].b - main[1].b), 0.8, "NORITSU 섀도 그레이는 중립(b*)")

        // 3) 톤(문서 방향: 개방 섀도 + 저대비 미드 + highlight retention):
        //    섀도는 지각적으로 분명하게 개방되고, 명부는 리프트되지 않으며(보존 숄더),
        //    미드-섀도 계조 간격이 MAIN 보다 좁아진다(저대비 형태).
        XCTAssertGreaterThan(nor[1].l, main[1].l + 2.0, "NORITSU 섀도 개방(muted black/airy)")
        XCTAssertLessThan(nor[5].l, main[5].l + 0.15, "NORITSU 명부는 리프트 금지(retention 숄더)")
        XCTAssertGreaterThan(nor[1].l - main[1].l, nor[0].l - main[0].l,
            "NORITSU 리프트는 섀도가 미드보다 커야 한다(플랫/에어리 형태)")
        XCTAssertLessThan(nor[0].l - nor[1].l, (main[0].l - main[1].l) - 1.0,
            "NORITSU 미드-섀도 간격이 MAIN 보다 좁아야 한다(저대비)")

        // 4) 스킨(2026-07-23 재설계): FUJI 골든(옐로 쪽 +회전) vs NORITSU 핑크/피치(레드 쪽
        //    −회전) — 문헌 다수가 수렴하는 두 실기의 반대 정체성. 회전은 bounded(≤4°)로
        //    왜곡 없이 방향만 싣는다.
        let norDoc = ScannerTargetGrade.documentedCharacter(
            target: .noritsu, filmType: .colorNegative, monochrome: false)!
        XCTAssertFalse(norDoc.hueAnchors.isEmpty, "NORITSU 에 hue 개성 앵커가 있어야 한다(재설계)")
        for anchor in norDoc.hueAnchors {
            XCTAssertLessThanOrEqual(abs(anchor.rotateDegrees), 4.0, "HS hue 회전은 bounded(≤4°)")
            XCTAssertTrue((0.94...1.08).contains(anchor.chromaGain), "HS hue 게인은 bounded")
        }
        let mainSkinHue = atan2(main[2].b, main[2].a)
        let norSkinHue = atan2(nor[2].b, nor[2].a)
        let fujiSkinHue = atan2(fuji[2].b, fuji[2].a)
        XCTAssertLessThan(norSkinHue, mainSkinHue - 0.03,
            "NORITSU 스킨은 핑크/피치 쪽(레드 방향 회전)이어야 한다")
        XCTAssertGreaterThan(norSkinHue, mainSkinHue - 0.12,
            "NORITSU 핑크 스킨 회전은 bounded(왜곡 금지)")
        XCTAssertGreaterThan(fujiSkinHue - norSkinHue, 0.05,
            "FUJI 골든 vs NORITSU 핑크 — 스킨 정체성이 반대로 갈려야 한다")

        // 5) 채도: FUJI 하이라이트 채도↑(실측). 섀도는 실측 탈채도를 미적용(사용자 지시)
        //    — 탈채도 밴드(gain<1)가 구조적으로 없어야 하고, 어두운 유채의 잔여 채도 감소는
        //    실측 중립축 a*−(그린) 캐스트의 부수 효과 5% 이내만 허용한다.
        let fujiDoc = ScannerTargetGrade.documentedCharacter(
            target: .sp3000, filmType: .colorNegative, monochrome: false)!
        let fujiShadowBand = fujiDoc.chromaBands.min { $0.luma < $1.luma }!
        XCTAssertGreaterThanOrEqual(fujiShadowBand.gain, 1.0, "FUJI 섀도 탈채도 밴드 금지")
        XCTAssertGreaterThan(chroma(fuji[3]), chroma(main[3]), "FUJI 밝은 유채는 채도↑")
        XCTAssertGreaterThanOrEqual(chroma(fuji[4]), chroma(main[4]) * 0.95,
            "FUJI 어두운 유채가 탈색(섀도 탈채도)되면 안 된다")

        // 6) NORITSU 채도(재설계: 미드 중심 색 에너지 + 파스텔 명부): 명부 유채는 뚜렷이
        //    뮤트(파스텔), 미드 부근 유채는 MAIN 근처(±12%)를 유지하되 FUJI 의 부스트보다
        //    뚜렷이 낮다. 섀도 유채는 탈색 금지(밴드 1.0).
        XCTAssertLessThan(chroma(nor[6]), chroma(main[6]) - 0.5, "NORITSU 파스텔 명부 뮤트")
        XCTAssertGreaterThanOrEqual(chroma(nor[6]), chroma(main[6]) * 0.85,
            "NORITSU 파스텔 뮤트는 완만해야 한다(과도한 탈색 금지)")
        XCTAssertEqual(chroma(nor[3]), chroma(main[3]), accuracy: chroma(main[3]) * 0.12,
            "NORITSU 밝은 유채는 MAIN 근처(미드 에너지, 과장 금지)")
        XCTAssertGreaterThan(chroma(fuji[3]), chroma(nor[3]) * 1.10,
            "FUJI/NORITSU 명부 채도 정체성이 뚜렷이 갈려야 한다")
        XCTAssertGreaterThanOrEqual(chroma(nor[4]), chroma(main[4]) * 0.95,
            "NORITSU 어두운 유채가 탈색되면 안 된다")

        // 7) F135(소비자 미니랩 인화 룩, 2026-07-23 신설): 깊은 인화 블랙 + 밝은 미드 펀치 +
        //    웜-골드 그레이 + 헬시 골든 스킨 + 경쾌한 채도.
        let f135 = labs(.f135)
        XCTAssertLessThan(f135[1].l, main[1].l - 0.5, "F135 인화 블랙(섀도가 MAIN 보다 깊음)")
        XCTAssertGreaterThan(f135[0].l, main[0].l + 0.8, "F135 미드는 경쾌하게 밝다(인화 밝기)")
        XCTAssertLessThan(f135[5].l, main[5].l + 1.0, "F135 명부 리프트는 온건(retention)")
        XCTAssertGreaterThan(f135[0].b, main[0].b + 0.8, "F135 mid gray 는 웜-골드(b*↑)")
        // 축 직교성(2026-07-23 QA 증폭): HS 피치 = a*(마젠타) 우세, F135 골드 = b*(옐로) 우세.
        // 같은 웜 계열이라도 축이 달라야 흐린 장면에서 서로 상쇄되지 않는다.
        XCTAssertGreaterThan((nor[0].a - main[0].a) - (f135[0].a - main[0].a), 0.8,
            "HS 피치는 F135 골드보다 a*(마젠타) 우세여야 한다")
        XCTAssertGreaterThan((f135[0].b - main[0].b) - (nor[0].b - main[0].b), 0.5,
            "F135 골드는 HS 피치보다 b*(옐로) 우세여야 한다")
        let f135SkinHue = atan2(f135[2].b, f135[2].a)
        XCTAssertGreaterThan(f135SkinHue, mainSkinHue, "F135 스킨은 골든 쪽(+회전)")
        XCTAssertLessThan(f135SkinHue, fujiSkinHue, "F135 골든 회전은 FUJI 보다 온건해야 한다")
        XCTAssertGreaterThan(chroma(f135[2]), chroma(main[2]) * 1.05, "F135 스킨은 헬시(채도 리치)")
        XCTAssertGreaterThan(chroma(f135[3]), chroma(main[3]) * 1.05, "F135 원색은 경쾌하게 리치")
        XCTAssertGreaterThan(chroma(fuji[3]), chroma(f135[3]),
            "F135 펀치는 FUJI 명부 블레이즈보다 온건해야 한다")
        XCTAssertGreaterThanOrEqual(chroma(f135[4]), chroma(main[4]) * 0.95,
            "F135 어두운 유채가 탈색되면 안 된다")

        // 8) HR(프로 랩 정밀 인화 룩, 2026-07-23 신설/QA 증폭): 솔리드 블랙 + 노출 규율 미드 +
        //    쿨-클린 그레이(웜 계열과 반대 축) + 리치 딥 블루 + 충실 스킨 + 명부 숄더.
        let hr = labs(.hr)
        XCTAssertLessThan(hr[1].l, main[1].l - 1.0, "HR 솔리드 블랙(섀도가 MAIN 보다 깊음)")
        XCTAssertLessThan(abs(hr[0].l - main[0].l), 1.2, "HR 미드는 노출 규율(거의 중립)")
        XCTAssertLessThan(hr[5].l, main[5].l + 0.15, "HR 명부 보존 숄더(리프트 금지)")
        XCTAssertLessThan(hr[0].b, main[0].b - 0.8, "HR 그레이는 쿨-클린(b*↓ — 웜 계열과 반대 축)")
        XCTAssertGreaterThan(hr[0].b, main[0].b - 3.5, "HR 쿨 드리프트는 bounded")
        XCTAssertGreaterThan(f135[0].b, hr[0].b, "F135 웜-골드가 HR 쿨-클린보다 웜이어야 한다")
        XCTAssertGreaterThan(chroma(hr[7]), chroma(main[7]) * 1.03, "HR 블루는 리치(개선된 블루 응답 방향)")
        XCTAssertGreaterThan(chroma(hr[7]), chroma(nor[7]), "HR 블루 리치 vs HS 블루 소프트 분리")
        let hrSkinHue = atan2(hr[2].b, hr[2].a)
        XCTAssertLessThan(abs(hrSkinHue - mainSkinHue), 0.045, "HR 스킨은 충실(스타일화 회전 최소)")
    }

    /// MAIN/PRINT/RESCUE 는 documentedCharacter 가 nil 이라 개성 그레이드가 붙지 않는다.
    func testDocumentedCharacterOnlyForScannerEmulationTargets() {
        for target in [DevelopTarget.main, .print, .rescue] {
            XCTAssertNil(
                ScannerTargetGrade.documentedCharacter(target: target, filmType: .colorNegative, monochrome: false),
                "\(target.rawValue) 에 문서 개성이 붙으면 안 된다")
        }
        XCTAssertNotNil(
            ScannerTargetGrade.documentedCharacter(target: .noritsu, filmType: .colorNegative, monochrome: false))
        XCTAssertNotNil(
            ScannerTargetGrade.documentedCharacter(target: .sp3000, filmType: .colorNegative, monochrome: false))
        XCTAssertNotNil(
            ScannerTargetGrade.documentedCharacter(target: .f135, filmType: .colorNegative, monochrome: false))
        XCTAssertNotNil(
            ScannerTargetGrade.documentedCharacter(target: .hr, filmType: .colorNegative, monochrome: false))
        // 흑백은 색 성분을 버리고 톤만 남긴다.
        let bw = ScannerTargetGrade.documentedCharacter(target: .sp3000, filmType: .bwNegative, monochrome: true)
        XCTAssertNotNil(bw)
        XCTAssertTrue(bw?.neutralBins.isEmpty ?? false)
        XCTAssertTrue(bw?.hueAnchors.isEmpty ?? false)
        XCTAssertTrue(bw?.chromaBands.isEmpty ?? false)

        // 포지티브(슬라이드)도 문서 개성이 붙되(4개 조합 전부 적용), 개입은 네거티브보다 약하다.
        let neg = ScannerTargetGrade.documentedCharacter(target: .sp3000, filmType: .colorNegative, monochrome: false)!
        let pos = ScannerTargetGrade.documentedCharacter(target: .sp3000, filmType: .colorPositive, monochrome: false)!
        let negDelta = abs(neg.tone[1] - neg.toneXs[1])
        let posDelta = abs(pos.tone[1] - pos.toneXs[1])
        XCTAssertGreaterThan(posDelta, 0, "포지티브도 개성이 있어야 한다")
        XCTAssertGreaterThan(negDelta, posDelta, "포지티브 개입은 네거티브보다 약해야 한다")
    }
}
