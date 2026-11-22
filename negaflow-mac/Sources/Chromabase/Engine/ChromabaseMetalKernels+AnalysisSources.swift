extension ChromabaseMetalKernels {
    static let analysisKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "sceneAreaSamples", body: """
    [[stitchable]] float4 sceneAreaSamples(coreimage::sampler src, float4 bounds,
                                         float2 grid, coreimage::destination dest) {
        float2 cell = floor(dest.coord());
        float2 low = cell * bounds.zw / grid;
        float2 high = (cell + 1.0) * bounds.zw / grid;
        // 칸 평균(premultiplied)과 덮인 정도(알파 평균)를 함께 돌려준다. 원근 보정의 빈 곳(알파 0)을
        // 검정으로 세지 않도록 호출부가 덜 덮인 칸을 뺀다. 불투명한 그림은 알파가 1 이라 예전과 같다.
        float4 sum = float4(0.0);
        float weightSum = 0.0;
        for (int y = int(floor(low.y)); y < int(ceil(high.y)); ++y) {
            float wy = max(0.0, min(high.y, float(y + 1)) - max(low.y, float(y)));
            for (int x = int(floor(low.x)); x < int(ceil(high.x)); ++x) {
                float weight = wy * max(0.0, min(high.x, float(x + 1)) - max(low.x, float(x)));
                float4 p = src.sample(src.transform(bounds.xy + float2(x + 0.5, y + 0.5)));
                sum += p * weight;
                weightSum += weight;
            }
        }
        return sum / max(weightSum, 1e-8);
    }
    """),
        MetalKernelSource(name: "luminanceLevels", body: """
    // neutralLift(디지털 원본)이면 검정 들어 올리기(bias > 0)를 **무채색으로 더한다.** 비율로
    // 곱하면 y 가 0 에 가까운 화소의 채널비가 bias/y 만큼 커져 8bit (0,0,1) 이 (0,0,106) 파란
    // 점이 된다. 검정 자르기(bias ≤ 0)는 비율 그대로이고, 휘도 결과는 둘 다 y·scale + bias 다.
    // 필름 스캔(neutralLift 0)은 앞 판 식 그대로다.
    [[stitchable]] float4 luminanceLevels(coreimage::sample_t src, float scale, float bias, float neutralLift) {
        float y = dot(src.rgb, float3(0.2126, 0.7152, 0.0722));
        float mapped = clamp(y * scale + bias, 0.0, 10000.0);
        float fill = max(bias, 0.0);
        float lift = neutralLift > 0.5 ? fill : 0.0;
        float3 color = y > 1e-8 ? src.rgb * (max(mapped - lift, 0.0) / y) + float3(lift) : float3(fill);
        return float4(color, src.a);
    }
    """)
    ]
}
