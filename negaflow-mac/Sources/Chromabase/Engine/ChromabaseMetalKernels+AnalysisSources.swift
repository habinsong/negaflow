extension ChromabaseMetalKernels {
    static let analysisKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "sceneAreaSamples", body: """
    [[stitchable]] float4 sceneAreaSamples(coreimage::sampler src, float4 bounds,
                                         float2 grid, coreimage::destination dest) {
        float2 cell = floor(dest.coord());
        float2 low = cell * bounds.zw / grid;
        float2 high = (cell + 1.0) * bounds.zw / grid;
        float3 sum = float3(0.0);
        float weightSum = 0.0;
        for (int y = int(floor(low.y)); y < int(ceil(high.y)); ++y) {
            float wy = max(0.0, min(high.y, float(y + 1)) - max(low.y, float(y)));
            for (int x = int(floor(low.x)); x < int(ceil(high.x)); ++x) {
                float weight = wy * max(0.0, min(high.x, float(x + 1)) - max(low.x, float(x)));
                float4 p = src.sample(src.transform(bounds.xy + float2(x + 0.5, y + 0.5)));
                sum += p.rgb * weight;
                weightSum += weight;
            }
        }
        return float4(sum / max(weightSum, 1e-8), 1.0);
    }
    """),
        MetalKernelSource(name: "luminanceLevels", body: """
    [[stitchable]] float4 luminanceLevels(coreimage::sample_t src, float scale, float bias) {
        float y = dot(src.rgb, float3(0.2126, 0.7152, 0.0722));
        float mapped = clamp(y * scale + bias, 0.0, 10000.0);
        float3 color = y > 1e-8 ? src.rgb * (mapped / y) : float3(max(bias, 0.0));
        return float4(color, src.a);
    }
    """)
    ]
}
