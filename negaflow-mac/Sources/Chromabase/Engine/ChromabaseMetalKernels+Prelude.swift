import CoreImage

// 모든 커널 라이브러리가 앞에 붙이는 공용 헤더·인라인 헬퍼. 커널은 여기에 두지 않는다 —
// 한 라이브러리에 stitchable 커널이 둘 이상 있으면 Core Image 가 체인 프로그램을 혼동한다.
extension ChromabaseMetalKernels {
    static let prelude = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    // ── HSL 헬퍼 (Color Mixer / Calibration 공용) ──
    inline float3 rgb2hsl(float3 c) {
        float maxc = max(c.r, max(c.g, c.b));
        float minc = min(c.r, min(c.g, c.b));
        float l = (maxc + minc) * 0.5;
        float h = 0.0, s = 0.0;
        float d = maxc - minc;
        if (d > 1e-5) {
            s = l > 0.5 ? d / (2.0 - maxc - minc) : d / (maxc + minc);
            if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
            else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
            else                  h = (c.r - c.g) / d + 4.0;
            h /= 6.0;
        }
        return float3(h, s, l);
    }

    inline float hue2rgb(float p, float q, float t) {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }

    inline float3 hsl2rgb(float3 hsl) {
        float h = hsl.x, s = hsl.y, l = hsl.z;
        if (s < 1e-5) return float3(l);
        float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        float p = 2.0 * l - q;
        return float3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
    }

    // Exposure is scene-linear and can legitimately produce values outside [0, 1]. Tone masks and
    // smoothstep curves below are display-referred, so bring only their input into that domain while
    // preserving luma and hue. Per-channel hard clipping here would create colored highlight bands.
    inline float3 toneSafeUnitRGB(float3 rgb) {
        float y = clamp(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
        float3 chroma = rgb - float3(y);
        float tr = chroma.r > 1e-5 ? (1.0 - y) / chroma.r : (chroma.r < -1e-5 ? (-y) / chroma.r : 1.0);
        float tg = chroma.g > 1e-5 ? (1.0 - y) / chroma.g : (chroma.g < -1e-5 ? (-y) / chroma.g : 1.0);
        float tb = chroma.b > 1e-5 ? (1.0 - y) / chroma.b : (chroma.b < -1e-5 ? (-y) / chroma.b : 1.0);
        float t = clamp(min(1.0, min(tr, min(tg, tb))), 0.0, 1.0);
        return clamp(float3(y) + t * chroma, 0.0, 1.0);
    }

    inline float srgbEncodeLuma(float v) {
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
    }

    inline float srgbDecodeLuma(float v) {
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    }

    // 휘도 목표를 화소에 싣는다. 어둡게 할 때는 채널 비율을 보존한다 — 같은 값을 빼면 가장 작은
    // 채널이 먼저 0 에 닿아 암부의 약한 색이 원색으로 폭주한다(R/B 1.2 → 대비 +1 에서 131).
    // 밝힐 때는 기존처럼 같은 값을 더한다(끝점 앵커·옅은 리프트 질감 유지).
    inline float3 withLuma(float3 rgb, float y, float newY) {
        if (newY < y && y > 1e-6) { return rgb * (newY / y); }
        return rgb + float3(newY - y);
    }

    // ── 디지털 소스 전용 필름 시뮬레이션 ──
    //
    // 아래 커널들은 isDigitalSource 경로에서만 호출된다. 필름 스캔은 이미 이 물리를 픽셀에
    // 담고 있으므로 같은 응답을 두 번 얹지 않는다.

    /// 부드러운 상한. t≥0 에서 limit 로 단조 수렴하되 t≪limit 구간의 기울기 1을 보존한다.
    /// n 이 작을수록 완만하게 눕는다(= 관용도가 넓은 유제).
    inline float softLimit(float t, float limit, float n) {
        if (limit <= 1e-6) return 0.0;
        float r = max(t, 0.0) / limit;
        return t / pow(1.0 + pow(r, n), 1.0 / n);
    }

    inline float3 softLimit3(float3 t, float limit, float n) {
        return float3(softLimit(t.x, limit, n), softLimit(t.y, limit, n), softLimit(t.z, limit, n));
    }

    inline float3 digitalLinearToSRGB(float3 c) {
        float3 lo = c * 12.92;
        float3 hi = 1.055 * pow(max(c, float3(0.0)), float3(1.0 / 2.4)) - 0.055;
        return select(hi, lo, c <= float3(0.0031308));
    }

    inline float3 digitalSRGBToLinear(float3 c) {
        float3 lo = c / 12.92;
        float3 hi = pow(max((c + 0.055) / 1.055, float3(0.0)), float3(2.4));
        return select(hi, lo, c <= float3(0.04045));
    }

    inline float digitalHueDegrees(float3 c) {
        float mx = max(c.r, max(c.g, c.b));
        float mn = min(c.r, min(c.g, c.b));
        float d = mx - mn;
        if (d <= 1e-6) return 0.0;
        float h;
        if (mx == c.r)      h = (c.g - c.b) / d;
        else if (mx == c.g) h = 2.0 + (c.b - c.r) / d;
        else                h = 4.0 + (c.r - c.g) / d;
        h *= 60.0;
        return h < 0.0 ? h + 360.0 : h;
    }

    // 6색 앵커(R,Y,G,C,B,M)를 hue 원형 선형보간.
    inline float digitalHueBand(float hue, float4 a, float4 b) {
        float anchors[6] = { a.x, a.y, a.z, a.w, b.x, b.y };
        float seg = hue / 60.0;
        float base = floor(seg);
        int i = int(base) % 6;
        int j = (i + 1) % 6;
        float f = seg - base;
        return anchors[i] * (1.0 - f) + anchors[j] * f;
    }
    """
}
