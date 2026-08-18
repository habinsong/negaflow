// 스캐너 타겟 프로파일 그레이드입니다. **엔진에서 가장 비싼 화소별 커널**입니다.
//
// macOS  : `ScannerTargetGrade+Apply.swift` — 64³ `CIColorCubeWithColorSpace` +
//          `boundedRelativeGrade`(`ChromabaseMetalKernels.swift:531`)
// CPU 판 : `imaging/scanner_target_grade.cpp` `apply_profile_grade` +
//          `scanner_target_response.cpp` `transformed_srgb` / `gamut_scale`
//
// ☠️ **macOS 와 알고리즘이 다릅니다.** macOS 는 같은 수식을 64³ 격자에서 **262,144번**
//    풀어 큐브를 만들고 그것을 보간해 씁니다. Windows 는 **화소마다** 풉니다 —
//    24MP 에서 17,300,000번, macOS 의 **66배**입니다. 이 셰이더는 Windows 의 셈을
//    그대로 옮긴 것이고, 큐브로 바꾸는 것은 값이 달라지는 **별건**입니다.
//
// ☠️ **CPU 는 `double` 이고 이것은 float 입니다.** sRGB 왕복은 CPU 도 이미 float 로
//    내려서 돌지만(`scanner_target_color.cpp:23-29` 가 `static_cast<float>` 합니다),
//    Lab 왕복과 hue/chroma 응답은 `double` 입니다. 오차는 시험이 재서 적습니다.
//
// ☠️ `domainWeight` 는 **sRGB 코드 좌표**에서 계산합니다. working-linear 에서 계산하면
//    linear 0.01(sRGB ≈ 0.10)이 잘못 반감됩니다 — macOS 커널 주석이 못박은 자리입니다.

#include "tone_shared.hlsli"

#define NEGAFLOW_TONE_KNOTS 9
#define NEGAFLOW_NEUTRAL_BINS 10
#define NEGAFLOW_HUE_ANCHORS 8
#define NEGAFLOW_CHROMA_BANDS 3

cbuffer ScannerTargetGradeConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // 톤 매듭의 입력 위치와, 호스트가 이미 세기·앵커까지 반영해 만든 출력값입니다.
    // ⚠️ 상수 버퍼의 배열은 원소마다 16바이트라 `float4[3]` 으로 묶고 `[i>>2][i&3]` 로 읽습니다.
    float4 ToneXs[3];
    float4 ToneYs[3];
    // (luma, a, b, _)
    float4 NeutralBins[NEGAFLOW_NEUTRAL_BINS];
    // (hue, gain, rotation, _)
    float4 HueAnchors[NEGAFLOW_HUE_ANCHORS];
    // (luma, gain, _, _)
    float4 ChromaBands[NEGAFLOW_CHROMA_BANDS];
    uint NeutralCount;
    uint HueCount;
    float Strength;
    float ChromaKeep;
    uint Monochrome;
    float3 Padding1;
};

static const float NegaflowPi = 3.14159265358979323846;

float ToneX(int index) { return ToneXs[index >> 2][index & 3]; }
float ToneY(int index) { return ToneYs[index >> 2][index & 3]; }

// `scanner_target_color.cpp` `clamp`/`smoothstep` 과 같습니다.
float Smoothstep2(float low, float high, float value) {
    float t = clamp((value - low) / max(high - low, 1.0e-9), 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

// `lab_f`. HLSL 에 `cbrt` 가 없어 `pow(x, 1/3)` 을 씁니다 — 이 분기의 입력은 항상 양수라
// 정의역 문제가 없습니다.
float LabF(float value) {
    const float delta = 6.0 / 29.0;
    // `abs` 는 여기서 **항등**입니다 — 이 가지는 `value > delta³ > 0` 일 때만 돕니다.
    // fxc 가 `pow` 의 밑을 정적으로 양수라고 증명하지 못해 경고(X3571)를 내므로 답니다.
    return value > delta * delta * delta
        ? pow(abs(value), 1.0 / 3.0)
        : value / (3.0 * delta * delta) + 4.0 / 29.0;
}

float LabFInverse(float value) {
    const float delta = 6.0 / 29.0;
    return value > delta
        ? value * value * value
        : 3.0 * delta * delta * (value - 4.0 / 29.0);
}

// `srgb_to_lab`. 입력은 sRGB 코드 좌표입니다.
float3 SrgbToLab(float3 value) {
    float r = SrgbEncodedToLinear(value.r);
    float g = SrgbEncodedToLinear(value.g);
    float b = SrgbEncodedToLinear(value.b);
    float x = ((0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b)) / 0.95047;
    float y = (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b);
    float z = ((0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b)) / 1.08883;
    float fx = LabF(x);
    float fy = LabF(y);
    float fz = LabF(z);
    return float3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

// `lab_to_extended_srgb`. 결과는 sRGB 코드 좌표이고 **[0,1] 밖으로 나갈 수 있습니다** —
// 자르지 마십시오. 확장값 보존 계약입니다.
float3 LabToExtendedSrgb(float3 lab) {
    float fy = (lab.x + 16.0) / 116.0;
    float fx = fy + lab.y / 500.0;
    float fz = fy - lab.z / 200.0;
    float x = LabFInverse(fx) * 0.95047;
    float y = LabFInverse(fy);
    float z = LabFInverse(fz) * 1.08883;
    return float3(
        LinearToSrgbEncoded((3.2404542 * x) - (1.5371385 * y) - (0.4985314 * z)),
        LinearToSrgbEncoded((-0.9692660 * x) + (1.8760108 * y) + (0.0415560 * z)),
        LinearToSrgbEncoded((0.0556434 * x) - (0.2040259 * y) + (1.0572252 * z)));
}

float TargetLuma(float3 value) {
    return (0.2126 * value.r) + (0.7152 * value.g) + (0.0722 * value.b);
}

// `relative_tone`. 끝점 (0,0)/(1,1) 을 고정한 채 매듭 사이를 잇습니다 —
// 마지막 매듭을 클리핑점으로 다루면 SP-3000·HS 명부가 눌립니다(CPU 주석).
float RelativeTone(float value) {
    if (value <= ToneX(0)) {
        return clamp(value * ToneY(0) / max(ToneX(0), 1.0e-9), 0.0, 1.0);
    }
    int last = NEGAFLOW_TONE_KNOTS - 1;
    if (value >= ToneX(last)) {
        float remaining = max(1.0 - ToneX(last), 1.0e-9);
        return clamp(
            ToneY(last) + ((1.0 - ToneY(last)) * (value - ToneX(last)) / remaining),
            0.0,
            1.0);
    }
    [unroll]
    for (int i = 1; i < NEGAFLOW_TONE_KNOTS; ++i) {
        if (value <= ToneX(i)) {
            float f = (value - ToneX(i - 1)) / max(ToneX(i) - ToneX(i - 1), 1.0e-9);
            float lowDelta = ToneY(i - 1) - ToneX(i - 1);
            float highDelta = ToneY(i) - ToneX(i);
            return clamp(value + lowDelta + ((highDelta - lowDelta) * f), 0.0, 1.0);
        }
    }
    return ToneY(last);
}

// `chroma_band_gain`. 밴드 사이는 **로그 공간 선형보간**입니다.
float ChromaBandGain(float value, float keep) {
    uint hi = 0u;
    while (hi + 1u < uint(NEGAFLOW_CHROMA_BANDS) && value > ChromaBands[hi].x) {
        ++hi;
    }
    float gain = ChromaBands[hi].y;
    if (hi > 0u && value < ChromaBands[hi].x) {
        float lowLuma = ChromaBands[hi - 1u].x;
        float lowGain = ChromaBands[hi - 1u].y;
        float highLuma = ChromaBands[hi].x;
        float highGain = ChromaBands[hi].y;
        float f = (value - lowLuma) / max(highLuma - lowLuma, 1.0e-6);
        gain = exp(log(lowGain) + ((log(highGain) - log(lowGain)) * f));
    }
    // `abs` 는 여기서도 항등입니다 — 호스트가 표의 이득이 전부 양수인지 확인하고
    // 아니면 디스패치 자체를 거절합니다(`gpu_scanner_target_grade.cpp`).
    return pow(abs(gain), keep);
}

// `neutral_drift`.
float2 NeutralDrift(float value, float scale) {
    if (NeutralCount == 0u) {
        return float2(0.0, 0.0);
    }
    if (value <= NeutralBins[0].x) {
        return float2(NeutralBins[0].y * scale, NeutralBins[0].z * scale);
    }
    uint last = NeutralCount - 1u;
    if (value >= NeutralBins[last].x) {
        return float2(NeutralBins[last].y * scale, NeutralBins[last].z * scale);
    }
    for (uint i = 1u; i < NeutralCount; ++i) {
        if (value <= NeutralBins[i].x) {
            float3 lo = NeutralBins[i - 1u].xyz;
            float3 hi = NeutralBins[i].xyz;
            float f = (value - lo.x) / max(hi.x - lo.x, 1.0e-6);
            return float2(
                (lo.y + ((hi.y - lo.y) * f)) * scale,
                (lo.z + ((hi.z - lo.z) * f)) * scale);
        }
    }
    return float2(0.0, 0.0);
}

// `hue_response`. 원형이라 마지막 앵커가 첫 앵커 앞으로 −360 만큼 당겨져 시작합니다.
float2 HueResponse(float hue, float scale, float keep) {
    hue = fmod(hue + 360.0, 360.0);
    if (hue < 0.0) {
        hue += 360.0;
    }
    uint last = HueCount - 1u;
    float previousHue = HueAnchors[last].x - 360.0;
    float previousGain = HueAnchors[last].y;
    float previousRotation = HueAnchors[last].z;
    for (uint i = 0u; i < HueCount; ++i) {
        float3 anchor = HueAnchors[i].xyz;
        if (hue <= anchor.x) {
            float f = (hue - previousHue) / max(anchor.x - previousHue, 1.0e-6);
            float logGain = log(previousGain) + ((log(anchor.y) - log(previousGain)) * f);
            float rotation = previousRotation + ((anchor.z - previousRotation) * f);
            return float2(exp(logGain * scale * keep), rotation * scale);
        }
        previousHue = anchor.x;
        previousGain = anchor.y;
        previousRotation = anchor.z;
    }
    float3 first = HueAnchors[0].xyz;
    float f = (hue - previousHue) / max(first.x + 360.0 - previousHue, 1.0e-6);
    float logGain = log(previousGain) + ((log(first.y) - log(previousGain)) * f);
    return float2(
        exp(logGain * scale * keep),
        (previousRotation + ((first.z - previousRotation) * f)) * scale);
}

// `transformed_srgb`. `reciprocal` 은 상대 프로파일을 되돌리는 방향입니다.
float3 TransformedSrgb(float3 input, bool reciprocal) {
    float inputLuma = TargetLuma(input);
    float3 lab = SrgbToLab(input);
    float mapped = RelativeTone(inputLuma);
    float delta = mapped - inputLuma;
    float mappedLuma = clamp(inputLuma + (reciprocal ? -delta : delta), 0.0, 1.0);
    float neutralL = SrgbToLab(float3(inputLuma, inputLuma, inputLuma)).x;
    float mappedL = SrgbToLab(float3(mappedLuma, mappedLuma, mappedLuma)).x;
    lab.x += mappedL - neutralL;

    if (Monochrome == 0u) {
        float chroma = sqrt((lab.y * lab.y) + (lab.z * lab.z));
        float colorTaper = Smoothstep2(0.02, 0.10, inputLuma) *
            (1.0 - Smoothstep2(0.90, 0.98, inputLuma));
        if (chroma > 1.0e-6) {
            float hue = atan2(lab.z, lab.y) * 180.0 / NegaflowPi;
            float2 response = HueResponse(hue, Strength, ChromaKeep);
            float band = pow(ChromaBandGain(inputLuma, ChromaKeep), Strength);
            if (reciprocal) {
                response.x = 1.0 / max(response.x, 1.0e-9);
                response.y = -response.y;
                band = 1.0 / max(band, 1.0e-9);
            }
            float gain = exp(log(max(response.x * band, 1.0e-9)) * colorTaper);
            float angle = atan2(lab.z, lab.y) + (response.y * colorTaper * NegaflowPi / 180.0);
            lab.y = chroma * gain * cos(angle);
            lab.z = chroma * gain * sin(angle);
        }

        float2 drift = NeutralDrift(inputLuma, Strength);
        if (reciprocal) {
            drift = -drift;
        }
        float taper = Smoothstep2(0.03, 0.10, inputLuma) *
            (1.0 - Smoothstep2(0.90, 0.97, inputLuma));
        // ☠️ 게이트가 쓰는 `chroma` 는 **hue 응답을 얹기 전** 값입니다
        //    (`scanner_target_response.cpp:139` 에서 잰 뒤 `:160` 에서 그대로 씁니다).
        //    얹은 뒤 값으로 게이트하면 채도가 커진 화소에서 중성 드리프트가 잘못 닫힙니다.
        float neutralGate = 1.0 - Smoothstep2(8.0, 28.0, chroma);
        float warmGate = Smoothstep2(0.22, 0.52, inputLuma);
        drift.x = clamp(drift.x, -4.0, 4.0);
        drift.y = clamp(drift.y, -4.0, 4.0);
        if (drift.x > 0.0) {
            drift.x *= warmGate;
        }
        if (drift.y > 0.0) {
            drift.y *= warmGate;
        }
        lab.y += drift.x * taper * neutralGate;
        lab.z += drift.y * taper * neutralGate;
    }
    return LabToExtendedSrgb(lab);
}

// `gamut_scale`. 두 후보(정방향·역방향) 중 어느 채널도 [0,1] 을 넘지 않는 최대 비율입니다.
float GamutScale(float3 input, float3 candidate, float3 reciprocal) {
    float scale = 1.0;
    [unroll]
    for (int side = 0; side < 2; ++side) {
        float3 output = side == 0 ? candidate : reciprocal;
        [unroll]
        for (int channel = 0; channel < 3; ++channel) {
            float from = input[channel];
            float delta = output[channel] - from;
            if (delta > 0.0) {
                scale = min(scale, (1.0 - from) / delta);
            } else if (delta < 0.0) {
                scale = min(scale, -from / delta);
            }
        }
    }
    return clamp(scale, 0.0, 1.0);
}

[numthreads(8, 8, 1)]
void ScannerTargetGradeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 encoded = float3(
        LinearToSrgbEncoded(source.r),
        LinearToSrgbEncoded(source.g),
        LinearToSrgbEncoded(source.b));
    float low = min(encoded.r, min(encoded.g, encoded.b));
    float high = max(encoded.r, max(encoded.g, encoded.b));
    float domainWeight = Smoothstep2(0.0, 0.02, low) * (1.0 - Smoothstep2(0.98, 1.0, high));
    if (domainWeight <= 0.0) {
        // CPU 의 `continue` 와 같은 자리입니다 — **원본 그대로** 나갑니다.
        Destination[coordinate] = source;
        return;
    }

    float3 candidate = TransformedSrgb(encoded, false);
    float3 reciprocal = TransformedSrgb(encoded, true);
    float scale = GamutScale(encoded, candidate, reciprocal);
    float3 graded = float3(
        SrgbEncodedToLinear(encoded.r + ((candidate.r - encoded.r) * scale)),
        SrgbEncodedToLinear(encoded.g + ((candidate.g - encoded.g) * scale)),
        SrgbEncodedToLinear(encoded.b + ((candidate.b - encoded.b) * scale)));
    Destination[coordinate] = float4(
        source.rgb + ((graded - source.rgb) * domainWeight),
        source.a);
}
