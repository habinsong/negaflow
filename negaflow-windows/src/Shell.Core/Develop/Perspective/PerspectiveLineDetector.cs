namespace Negaflow.Shell.Develop.Perspective;

/// <summary>곧은 선분 하나(정규좌표, y 아래)와 길이(픽셀)입니다.</summary>
public readonly record struct PerspectiveLineSegment(
    double StartX, double StartY, double EndX, double EndY, double Length);

/// <summary>
/// 변환 자동 모드가 쓰는 곧은 선분 찾기입니다. macOS <c>PerspectiveLineDetector</c> 와 같은 방식·같은
/// 기준입니다: 밝기 기울기가 뚜렷한 화소 가운데 가장자리 방향이 이웃과 비슷한 화소끼리 묶고, 묶음마다
/// 주성분으로 직선을 맞춰 가늘고 길며 방향이 고른 묶음만 남깁니다.
/// </summary>
public static class PerspectiveLineDetector
{
    public const int AnalysisLongEdge = 900;

    public static IReadOnlyList<PerspectiveLineSegment> Detect(
        float[] luma, int width, int height, int maximumSegments = 400)
    {
        ArgumentNullException.ThrowIfNull(luma);
        if (width < 16 || height < 16 || luma.Length != width * height)
        {
            return [];
        }
        float[] blurred = Blur(luma, width, height);
        int count = width * height;
        float[] magnitude = new float[count];
        float[] direction = new float[count];
        for (int y = 1; y < height - 1; ++y)
        {
            for (int x = 1; x < width - 1; ++x)
            {
                int i = (y * width) + x;
                float gx = (blurred[i - width + 1] + (2 * blurred[i + 1]) + blurred[i + width + 1])
                    - (blurred[i - width - 1] + (2 * blurred[i - 1]) + blurred[i + width - 1]);
                float gy = (blurred[i + width - 1] + (2 * blurred[i + width]) + blurred[i + width + 1])
                    - (blurred[i - width - 1] + (2 * blurred[i - width]) + blurred[i - width + 1]);
                magnitude[i] = MathF.Sqrt((gx * gx) + (gy * gy));
                float a = MathF.Atan2(gx, -gy);
                if (a < 0) { a += MathF.PI; }
                if (a >= MathF.PI) { a -= MathF.PI; }
                direction[i] = a;
            }
        }
        float threshold = EdgeThreshold(magnitude);
        if (threshold <= 0)
        {
            return [];
        }

        int[] parent = new int[count];
        Array.Fill(parent, -1);
        int Find(int i)
        {
            int root = i;
            while (parent[root] != root) { root = parent[root]; }
            int node = i;
            while (parent[node] != root)
            {
                int next = parent[node];
                parent[node] = root;
                node = next;
            }
            return root;
        }
        void Union(int a, int b)
        {
            int ra = Find(a), rb = Find(b);
            if (ra != rb) { parent[Math.Max(ra, rb)] = Math.Min(ra, rb); }
        }
        for (int i = 0; i < count; ++i)
        {
            if (magnitude[i] >= threshold) { parent[i] = i; }
        }
        const float tolerance = MathF.PI / 8;
        bool Similar(float a, float b)
        {
            float d = MathF.Abs(a - b);
            return MathF.Min(d, MathF.PI - d) < tolerance;
        }
        for (int y = 1; y < height - 1; ++y)
        {
            for (int x = 1; x < width - 1; ++x)
            {
                int i = (y * width) + x;
                if (parent[i] < 0) { continue; }
                foreach (int j in new[] { i + 1, i + width - 1, i + width, i + width + 1 })
                {
                    if (parent[j] >= 0 && Similar(direction[i], direction[j])) { Union(i, j); }
                }
            }
        }

        Dictionary<int, double[]> groups = [];
        for (int i = 0; i < count; ++i)
        {
            if (parent[i] < 0) { continue; }
            int root = Find(i);
            if (!groups.TryGetValue(root, out double[]? m))
            {
                m = new double[8];
                groups[root] = m;
            }
            double x = i % width, y = i / width;
            double a = direction[i] * 2.0;
            m[0] += 1; m[1] += x; m[2] += y; m[3] += x * x; m[4] += y * y; m[5] += x * y;
            m[6] += Math.Cos(a); m[7] += Math.Sin(a);
        }
        double longEdge = Math.Max(width, height);
        double minimumLength = Math.Max(12, longEdge * 0.04);
        List<PerspectiveLineSegment> segments = [];
        foreach (double[] m in groups.Values)
        {
            double n = m[0];
            if (n < minimumLength * 0.6) { continue; }
            double mx = m[1] / n, my = m[2] / n;
            double cxx = (m[3] / n) - (mx * mx);
            double cyy = (m[4] / n) - (my * my);
            double cxy = (m[5] / n) - (mx * my);
            double trace = cxx + cyy;
            double root = Math.Sqrt((((cxx - cyy) * (cxx - cyy)) / 4) + (cxy * cxy));
            double major = (trace / 2) + root, minor = Math.Max((trace / 2) - root, 0);
            if (major <= 0) { continue; }
            double angle = 0.5 * Math.Atan2(2 * cxy, cxx - cyy);
            double length = Math.Sqrt(12 * major);
            double thickness = Math.Sqrt(12 * minor);
            double coherence = Math.Sqrt((m[6] * m[6]) + (m[7] * m[7])) / n;
            if (length < minimumLength || length < 6 * Math.Max(thickness, 1) || coherence < 0.8) { continue; }
            double dx = Math.Cos(angle) * length / 2, dy = Math.Sin(angle) * length / 2;
            segments.Add(new PerspectiveLineSegment(
                (mx - dx) / width, (my - dy) / height, (mx + dx) / width, (my + dy) / height, length));
        }
        return [.. segments.OrderByDescending(segment => segment.Length).Take(maximumSegments)];
    }

    internal static float EdgeThreshold(float[] magnitude)
    {
        int[] histogram = new int[1024];
        int total = 0;
        foreach (float m in magnitude)
        {
            if (m <= 0) { continue; }
            histogram[Math.Min((int)(m / 4 * 1023), 1023)] += 1;
            total += 1;
        }
        if (total == 0) { return 0; }
        int seen = 0;
        float percentile = 0;
        for (int bin = 0; bin < histogram.Length; ++bin)
        {
            seen += histogram[bin];
            if (seen >= total * 0.85)
            {
                percentile = bin / 1023f * 4;
                break;
            }
        }
        return MathF.Max(percentile, 0.08f * 4);
    }

    internal static float[] Blur(float[] input, int width, int height)
    {
        float[] horizontal = new float[input.Length];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                float l = input[(y * width) + Math.Max(x - 1, 0)];
                float c = input[(y * width) + x];
                float r = input[(y * width) + Math.Min(x + 1, width - 1)];
                horizontal[(y * width) + x] = (l + (2 * c) + r) / 4;
            }
        }
        float[] output = new float[input.Length];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                float u = horizontal[(Math.Max(y - 1, 0) * width) + x];
                float c = horizontal[(y * width) + x];
                float d = horizontal[(Math.Min(y + 1, height - 1) * width) + x];
                output[(y * width) + x] = (u + (2 * c) + d) / 4;
            }
        }
        return output;
    }
}
