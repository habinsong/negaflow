// macOS `DevelopFrameRenderer+Developed.swift` `renderDisplayCGImage`:
// DisplayGamutMap → SoftProof → OutputDither → createCGImage(.RGBA8).
// CPU 판: `pipeline/export/support/preview.cpp` `write_preview` 1:1 화소 경로.
//
// `tone_shared.hlsli` 를 끌어오지 않습니다 — 그 조각은 float UAV 를 `u0` 에 묶습니다.
// 수식은 그 파일의 `ToneSafeUnitRGB` / `LinearToSrgbEncoded` 와 같습니다.

Texture2D<float4> Source : register(t0);
RWTexture2D<unorm float4> DestBgra : register(u0);

cbuffer PreviewDisplayEncodeConstants : register(b0) {
    // 목표(=변환 뒤) 크기입니다. 변환이 없으면 원본 크기와 같습니다.
    uint2 Extent;
    uint2 Padding0;
    float3 ProofScale;
    float Padding1;
    float3 ProofBias;
    float Padding2;
    // ── 미룬 기하 변환 ────────────────────────────────────────────────────────
    // 회전·뒤집기·자르기는 **정수 자리 옮김뿐**이라 여기서 읽는 자리만 바꾸면 됩니다.
    // CPU `image_transform.cpp` 의 `orient` + `crop_image` 와 같은 식입니다.
    // `Rotation` 0/1/2/3 = 0°/90°/180°/270°, `Flips` 비트 1=수평 2=수직.
    uint2 SourceExtent;
    uint2 CropOrigin;
    uint Rotation;
    uint Flips;
    uint2 Padding3;
    // ── 원근(변환) ────────────────────────────────────────────────────────────
    // CPU `perspective_warp`: 원근 출력 화소 중심 → 역호모그래피 → 방위 적용 좌표에서
    // 이중선형(반 화소 이동, 가장자리 고정). 원본 밖은 흰색에 `UncoveredAlpha`.
    float4 InverseRow0;
    float4 InverseRow1;
    float4 InverseRow2;
    float2 PerspectiveOrigin;
    uint2 OrientedExtent;
    uint PerspectiveEnabled;
    float UncoveredAlpha;
    // 1 이면 알파에 커버리지를 씁니다(`PreviewTarget.coverage_alpha`). 0 이면 언제나 1.
    uint CoverageAlpha;
    uint Padding4;
};

// 방위를 적용한 좌표의 한 화소가 원본의 어느 화소인가. CPU `orient` 은 **출력에서 원본으로**
// 매핑하므로 여기서도 같은 방향으로 씁니다.
uint2 OrientedToSource(uint2 oriented) {
    uint ox = oriented.x;
    uint oy = oriented.y;
    if (Rotation == 1u) {
        ox = oriented.y;
        oy = SourceExtent.y - 1u - oriented.x;
    } else if (Rotation == 2u) {
        ox = SourceExtent.x - 1u - oriented.x;
        oy = SourceExtent.y - 1u - oriented.y;
    } else if (Rotation == 3u) {
        ox = SourceExtent.x - 1u - oriented.y;
        oy = oriented.x;
    }
    if ((Flips & 1u) != 0u) {
        ox = SourceExtent.x - 1u - ox;
    }
    if ((Flips & 2u) != 0u) {
        oy = SourceExtent.y - 1u - oy;
    }
    return uint2(ox, oy);
}

uint2 SourceCoordinate(uint2 destination) {
    return OrientedToSource(destination + CropOrigin);
}

float4 ReadOriented(uint2 oriented) {
    return Source[OrientedToSource(oriented)];
}

// 목표 화소의 값. 원근이 없으면 자리 옮김뿐이고, 있으면 CPU `perspective_warp` 와 같은 식으로
// 이중선형으로 읽습니다.
float4 SampleDestination(uint2 destination) {
    float4 result = float4(1.0, 1.0, 1.0, UncoveredAlpha);
    if (PerspectiveEnabled == 0u) {
        result = Source[SourceCoordinate(destination)];
    } else {
        float3 canvas = float3(PerspectiveOrigin + float2(destination + CropOrigin) + 0.5, 1.0);
        float z = dot(InverseRow2.xyz, canvas);
        float2 extent = float2(OrientedExtent);
        float2 mapped = float2(-1.0, -1.0);
        if (abs(z) > 1e-12) {
            mapped = float2(dot(InverseRow0.xyz, canvas), dot(InverseRow1.xyz, canvas)) / z;
        }
        bool inside = !any(isnan(mapped)) && !any(isinf(mapped)) &&
            mapped.x >= 0.0 && mapped.y >= 0.0 && mapped.x <= extent.x && mapped.y <= extent.y;
        if (inside) {
            float2 c = clamp(mapped - 0.5, float2(0.0, 0.0), extent - 1.0);
            uint2 p0 = uint2(floor(c));
            uint2 p1 = min(p0 + 1u, OrientedExtent - 1u);
            float2 t = c - float2(p0);
            float4 a = ReadOriented(p0);
            float4 b = ReadOriented(uint2(p1.x, p0.y));
            float4 d0 = ReadOriented(uint2(p0.x, p1.y));
            float4 d1 = ReadOriented(p1);
            float4 top = a + (b - a) * t.x;
            float4 bottom = d0 + (d1 - d0) * t.x;
            result = top + (bottom - top) * t.y;
        }
    }
    return result;
}

float3 ToneSafeUnitRGB(float3 rgb) {
    float y = clamp(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
    float3 chroma = rgb - float3(y, y, y);
    float tr = chroma.r > 1e-5 ? (1.0 - y) / chroma.r : (chroma.r < -1e-5 ? (-y) / chroma.r : 1.0);
    float tg = chroma.g > 1e-5 ? (1.0 - y) / chroma.g : (chroma.g < -1e-5 ? (-y) / chroma.g : 1.0);
    float tb = chroma.b > 1e-5 ? (1.0 - y) / chroma.b : (chroma.b < -1e-5 ? (-y) / chroma.b : 1.0);
    float t = clamp(min(1.0, min(tr, min(tg, tb))), 0.0, 1.0);
    return clamp(float3(y, y, y) + (t * chroma), 0.0, 1.0);
}

float LinearToSrgbEncoded(float linearValue) {
    float magnitude = abs(linearValue);
    if (magnitude <= 0.0031308) {
        return linearValue * 12.92;
    }
    float encoded = (1.055 * pow(magnitude, 1.0 / 2.4)) - 0.055;
    return linearValue < 0.0 ? -encoded : encoded;
}

float display_dither_offset(uint x, uint y, uint channel) {
    uint hash = (x * 0x9E3779B1u) ^ (y * 0x85EBCA77u) ^ (channel * 0xC2B2AE3Du);
    hash ^= hash >> 15u;
    hash *= 0x2545F491u;
    hash ^= hash >> 13u;
    float unit = float(hash >> 8u) / 16777215.0;
    return (unit - 0.5) / 255.0;
}

[numthreads(8, 8, 1)]
void PreviewDisplayEncodeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    // 디더는 **목표 좌표**로 뽑습니다(`write_preview` 와 같음). 읽는 자리만 바뀌고
    // 디더 무늬는 화면 좌표에 붙어 있어야 합니다.
    float4 source = SampleDestination(id.xy);
    float3 folded = ToneSafeUnitRGB(source.rgb);
    float encodedR = LinearToSrgbEncoded((folded.r * ProofScale.x) + ProofBias.x);
    float encodedG = LinearToSrgbEncoded((folded.g * ProofScale.y) + ProofBias.y);
    float encodedB = LinearToSrgbEncoded((folded.b * ProofScale.z) + ProofBias.z);
    encodedR = saturate(encodedR + display_dither_offset(id.x, id.y, 0u));
    encodedG = saturate(encodedG + display_dither_offset(id.x, id.y, 1u));
    encodedB = saturate(encodedB + display_dither_offset(id.x, id.y, 2u));
    // XAML / `write_preview` BGRA8. 커버리지를 실을 때는 `write_preview` 처럼 알파에 씁니다.
    float alpha = CoverageAlpha != 0u ? saturate(source.a) : 1.0;
    DestBgra[id.xy] = float4(encodedB, encodedG, encodedR, alpha);
}
