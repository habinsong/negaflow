#include "tone_shared.hlsli"

// CPU가 계산한 PCHIP 기울기와 같은 계수를 전달합니다.
cbuffer CustomColorTargetConstants : register(b0) {
    uint2 Extent; float2 Padding0;
    float4 Tone[10]; // x: 명도, y: 기울기
    float4 HueA[8]; // gain, density, shadow, mid
    float4 HueB[8]; // high, highlight hue, padding
    float4 Controls; // q, A, B, M
    float4 TintShadowMid;
    float4 TintHigh;
};
static const float Knots[10] = {0, 5, 10, 20, 35, 50, 65, 80, 90, 100};

float LabTransfer(float x) {
    if (x > 216.0 / 24389.0) { return pow(x, 1.0 / 3.0); }
    return ((24389.0 / 27.0) * x + 16) / 116;
}
float InverseLabTransfer(float x) {
    if (x > 6.0 / 29.0) { return x * x * x; }
    return (108.0 / 841.0) * (x - 4.0 / 29.0);
}
float3 LinearToLab(float3 rgb) {
    float3 xyz = float3(dot(rgb, float3(0.4124564, 0.3575761, 0.1804375)),
                        dot(rgb, float3(0.2126729, 0.7151522, 0.0721750)),
                        dot(rgb, float3(0.0193339, 0.1191920, 0.9503041)));
    float fx = LabTransfer(dot(xyz, float3(1.0478112, 0.0228866, -0.0501270)) / 0.96422);
    float fy = LabTransfer(dot(xyz, float3(0.0295424, 0.9904844, -0.0170491)));
    float fz = LabTransfer(dot(xyz, float3(-0.0092345, 0.0150436, 0.7521316)) / 0.82521);
    return float3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}
float3 LabToLinear(float3 lab) {
    float fy = (lab.x + 16) / 116;
    float3 xyz = float3(InverseLabTransfer(fy + lab.y / 500) * 0.96422,
                        InverseLabTransfer(fy), InverseLabTransfer(fy - lab.z / 200) * 0.82521);
    float3 d65 = float3(dot(xyz, float3(0.9555766, -0.0230393, 0.0631636)),
                        dot(xyz, float3(-0.0282895, 1.0099416, 0.0210077)),
                        dot(xyz, float3(0.0122982, -0.0204830, 1.3299098)));
    return float3(dot(d65, float3(3.2404542, -1.5371385, -0.4985314)),
                  dot(d65, float3(-0.9692660, 1.8760108, 0.0415560)),
                  dot(d65, float3(0.0556434, -0.2040259, 1.0572252)));
}
float ToneValue(float l) {
    if (l <= 0) { return Tone[0].x + l * Tone[0].y; }
    if (l >= 100) { return Tone[9].x + (l - 100) * Tone[9].y; }
    uint i = 0;
    [loop] while (i < 8 && l >= Knots[i + 1]) { ++i; }
    float dx = Knots[i + 1] - Knots[i], z = (l - Knots[i]) / dx;
    float z2 = z * z, z3 = z2 * z;
    return (2 * z3 - 3 * z2 + 1) * Tone[i].x + (z3 - 2 * z2 + z) * dx * Tone[i].y
        + (-2 * z3 + 3 * z2) * Tone[i + 1].x + (z3 - z2) * dx * Tone[i + 1].y;
}
float3 Grade(float3 lab) {
    float l = lab.x, c = length(lab.yz);
    float hue = c == 0 ? 0 : atan2(lab.z, lab.y) * (180.0 / 3.141592653589793) + 360;
    hue -= 360 * floor(hue / 360);
    float at = hue / 45;
    uint i = (uint)floor(at) % 8;
    float4 a = lerp(HueA[i], HueA[(i + 1) % 8], frac(at));
    float4 b = lerp(HueB[i], HueB[(i + 1) % 8], frac(at));
    float t = ToneValue(l) / 100, k = a.y * c / (c + 24);
    float dense = t < 0 ? t / (1 + k) : (t > 1 ? 1 + (1 + k) * (t - 1) : t / (1 + k * (1 - t)));
    float lout = 100 * dense, weight = smoothstep(2, 10, c);
    float gain = 1 + (a.x - 1) * weight;
    float graded = c * gain * (Controls.x + (1 - Controls.x) * smoothstep(0, 28, l));
    float excess = graded - 48;
    float base = graded <= 48 ? graded : 48 + excess / (1 + excess / 48);
    float drive = lerp(l, lout, Controls.w), v = max((drive - Controls.y) / (100 - Controls.y), 0);
    float cout = base / (1 + Controls.z * v * v * (1 + base / 80));
    float loss = base == 0 ? 0 : saturate((base - cout) / base);
    float rotation = l < 50 ? lerp(a.z, a.w, saturate((l - 20) / 30)) : lerp(a.w, b.x, saturate((l - 50) / 30));
    float angle = (hue + (rotation + b.y * loss) * weight) * (3.141592653589793 / 180);
    float2 tint;
    if (l < 20) { tint = TintShadowMid.xy * saturate(l / 20); }
    else if (l < 50) { tint = lerp(TintShadowMid.xy, TintShadowMid.zw, (l - 20) / 30); }
    else if (l < 80) { tint = lerp(TintShadowMid.zw, TintHigh.xy, (l - 50) / 30); }
    else { tint = TintHigh.xy * (1 - saturate((l - 80) / 20)); }
    return float3(lout, cout * float2(cos(angle), sin(angle)) + tint * (1 - smoothstep(25, 75, c)));
}
[numthreads(8, 8, 1)]
void CustomColorTargetMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) { return; }
    float4 source = Source[id.xy];
    Destination[id.xy] = source.a == 0 ? float4(0, 0, 0, 0) : float4(LabToLinear(Grade(LinearToLab(source.rgb))), source.a);
}
