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
};

// 목표 화소가 읽어야 할 원본 자리입니다. CPU `orient` 은 **출력에서 원본으로** 매핑하므로
// 여기서도 같은 방향으로 씁니다.
uint2 SourceCoordinate(uint2 destination) {
    uint2 oriented = destination + CropOrigin;
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
    float4 source = Source[SourceCoordinate(id.xy)];
    float3 folded = ToneSafeUnitRGB(source.rgb);
    float encodedR = LinearToSrgbEncoded((folded.r * ProofScale.x) + ProofBias.x);
    float encodedG = LinearToSrgbEncoded((folded.g * ProofScale.y) + ProofBias.y);
    float encodedB = LinearToSrgbEncoded((folded.b * ProofScale.z) + ProofBias.z);
    encodedR = saturate(encodedR + display_dither_offset(id.x, id.y, 0u));
    encodedG = saturate(encodedG + display_dither_offset(id.x, id.y, 1u));
    encodedB = saturate(encodedB + display_dither_offset(id.x, id.y, 2u));
    // XAML / `write_preview` BGRA8.
    DestBgra[id.xy] = float4(encodedB, encodedG, encodedR, 1.0);
}
