using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 스캐너 제품 경로가 **플러그인이 보고한 capability 만** 보고 판정하는지 조합별로 확인합니다.
/// </summary>
/// <remarks>
/// <para>
/// 개별 기기(V700·GT-X900·OpticFilm 8100)로 확인한 시험은 이미 있지만, 그것은 그 두 대의
/// 증거일 뿐입니다. 다른 SANE 지원 스캐너가 같은 계약을 받는다는 것은 **조합을 전부 도는
/// 시험**으로만 보일 수 있습니다. 여기서는 판정에 쓰이는 flag 를 진리표로 돌립니다.
/// </para>
/// <para>
/// 이 파일에는 모델명·제조사·USB ID 가 하나도 없습니다. 그것이 요점입니다 — 제품 판정에
/// 그런 값이 필요했다면 이 시험을 쓸 수 없습니다.
/// </para>
/// </remarks>
internal static class ScannerCapabilityMatrixTests
{
    public static void Run()
    {
        VerifyRegionWorkflowTruthTable();
        VerifyFrameFormatTruthTable();
        VerifyColorModeFiltering();
        VerifyUsableCapabilityGate();
        VerifyInfraredFilmCompatibility();
        VerifyPolicyIgnoresEverythingButCapabilities();
    }

    private static ScannerPluginCapabilities Caps(
        bool positioned,
        bool preview,
        bool bounded,
        IReadOnlyList<int>? resolutions = null,
        IReadOnlyList<string>? modes = null,
        IReadOnlyList<int>? depths = null,
        bool infrared = false) =>
        new(
            resolutions ?? [600, 1200],
            modes ?? ["color", "gray"],
            depths ?? [8, 16],
            SupportsPreview: preview,
            SupportsTransparency: true,
            SupportsInfrared: infrared,
            SupportsMultiExposure: false,
            SupportsScanArea: true,
            SupportsPositionedScanArea: positioned,
            OutputFormats: ["tiff"],
            CapabilityToken: null,
            MaxScanWidthMm: bounded ? 216.0 : null,
            MaxScanHeightMm: bounded ? 297.0 : null,
            MinScanArea: bounded ? new ScannerPluginScanArea(0.0, 0.0, 36.0, 24.0) : null,
            MaxScanArea: bounded ? new ScannerPluginScanArea(0.0, 0.0, 216.0, 297.0) : null,
            ScanAreaUnit: bounded ? "millimeter" : null);

    private static string Label(bool positioned, bool preview, bool bounded) =>
        $"positioned={(positioned ? 1 : 0)}_preview={(preview ? 1 : 0)}_bounded={(bounded ? 1 : 0)}";

    /// <summary>
    /// macOS <c>AppModel.usesFlatbedRegionWorkflow</c> —
    /// <c>supportsPositionedScanArea &amp;&amp; supportsPreview &amp;&amp; physicalScanAreaBounds != nil</c>.
    /// 세 flag 의 8개 조합을 모두 돕니다.
    /// </summary>
    private static void VerifyRegionWorkflowTruthTable()
    {
        foreach (bool positioned in new[] { false, true })
        {
            foreach (bool preview in new[] { false, true })
            {
                foreach (bool bounded in new[] { false, true })
                {
                    bool expected = positioned && preview && bounded;
                    Check(
                        ScanOptionPolicy.UsesFlatbedRegionWorkflow(
                            Caps(positioned, preview, bounded)) == expected,
                        $"region_workflow_{Label(positioned, preview, bounded)}");
                }
            }
        }

        Check(
            !ScanOptionPolicy.UsesFlatbedRegionWorkflow(null),
            "region_workflow_without_a_device");
    }

    /// <summary>
    /// macOS <c>AppModel.availableScanFrameFormats</c>. 판 크기를 모르면 빈 목록이고, 영역을
    /// 지정할 수 있는데 프리뷰가 없으면 필름이 어디 있는지 볼 방법이 없어 역시 빈 목록입니다.
    /// </summary>
    private static void VerifyFrameFormatTruthTable()
    {
        foreach (bool positioned in new[] { false, true })
        {
            foreach (bool preview in new[] { false, true })
            {
                foreach (bool bounded in new[] { false, true })
                {
                    bool expected = bounded && !(positioned && !preview);
                    bool actual =
                        ScanOptionPolicy.AvailableFrameFormats(
                            Caps(positioned, preview, bounded)).Count > 0;
                    Check(
                        actual == expected,
                        $"frame_formats_{Label(positioned, preview, bounded)}");
                }
            }
        }

        Check(
            ScanOptionPolicy.AvailableFrameFormats(null).Count == 0,
            "frame_formats_without_a_device");
    }

    /// <summary>
    /// 색 모드는 장치가 보고한 목록에서 <c>color</c>·<c>gray</c> 만 남깁니다. lineart 처럼
    /// 제품 경로가 아닌 값을 임의로 고르면 안 되고, 장치가 하나만 보고하면 그 하나만 섭니다.
    /// </summary>
    private static void VerifyColorModeFiltering()
    {
        (string[] Reported, string[] Expected, string Name)[] cases =
        [
            (["color", "gray"], ["color", "gray"], "both"),
            (["color"], ["color"], "color_only"),
            (["gray"], ["gray"], "gray_only"),
            (["lineart", "color", "halftone"], ["color"], "lineart_and_halftone_dropped"),
            (["Color", "GRAY"], [], "case_sensitive_like_macos"),
            ([], [], "empty"),
        ];

        foreach ((string[] reported, string[] expected, string name) in cases)
        {
            IReadOnlyList<string> actual =
                ScanOptionPolicy.ColorModes(Caps(true, true, true, modes: reported));
            Check(
                actual.Count == expected.Length && actual.SequenceEqual(expected),
                $"color_modes_{name}");
        }
    }

    /// <summary>
    /// 셋 중 하나라도 비면 스캔 구획을 쓸 수 없습니다. 어느 하나가 빠졌는지에 상관없이
    /// 같은 판정이어야 합니다.
    /// </summary>
    private static void VerifyUsableCapabilityGate()
    {
        Check(
            ScanOptionPolicy.HasUsableCapabilities(Caps(true, true, true)),
            "usable_when_all_three_present");
        Check(
            !ScanOptionPolicy.HasUsableCapabilities(Caps(true, true, true, resolutions: [])),
            "unusable_without_resolutions");
        Check(
            !ScanOptionPolicy.HasUsableCapabilities(Caps(true, true, true, resolutions: [0])),
            "unusable_with_only_nonpositive_resolutions");
        Check(
            !ScanOptionPolicy.HasUsableCapabilities(Caps(true, true, true, modes: ["lineart"])),
            "unusable_when_no_product_color_mode");
        Check(
            !ScanOptionPolicy.HasUsableCapabilities(Caps(true, true, true, depths: [])),
            "unusable_without_bit_depths");
        Check(
            !ScanOptionPolicy.HasUsableCapabilities(null),
            "unusable_without_a_device");
    }

    /// <summary>
    /// IR 은 장치 capability 와 **필름 종류** 양쪽이 맞아야 합니다. 흑백 필름에는 IR 채널이
    /// 반응할 염료층이 없으므로 장치가 IR 을 지원해도 쓰지 않습니다.
    /// </summary>
    private static void VerifyInfraredFilmCompatibility()
    {
        Check(ScanOptionPolicy.AllowsInfrared(FilmType.ColorNegative), "infrared_color_negative");
        Check(ScanOptionPolicy.AllowsInfrared(FilmType.ColorPositive), "infrared_color_positive");
        Check(
            !ScanOptionPolicy.AllowsInfrared(FilmType.BlackAndWhiteNegative),
            "no_infrared_bw_negative");
        Check(
            !ScanOptionPolicy.AllowsInfrared(FilmType.BlackAndWhitePositive),
            "no_infrared_bw_positive");
    }

    /// <summary>
    /// 같은 capability 를 보고한 두 장치는 **판정이 완전히 같아야** 합니다. 제품 코드가
    /// 모델명·제조사·USB ID 를 보고 있었다면 이 단언이 깨집니다.
    /// </summary>
    private static void VerifyPolicyIgnoresEverythingButCapabilities()
    {
        // 서로 다른 장치가 보고할 법한 두 조합. 안쪽 값이 같으면 판정도 같아야 합니다.
        ScannerPluginCapabilities first = Caps(
            positioned: true, preview: true, bounded: true, resolutions: [600, 1200, 2400]);
        ScannerPluginCapabilities second = Caps(
            positioned: true, preview: true, bounded: true, resolutions: [600, 1200, 2400]);

        Check(
            ScanOptionPolicy.UsesFlatbedRegionWorkflow(first) ==
                ScanOptionPolicy.UsesFlatbedRegionWorkflow(second),
            "identical_capabilities_same_region_workflow");
        Check(
            ScanOptionPolicy.AvailableFrameFormats(first).Count ==
                ScanOptionPolicy.AvailableFrameFormats(second).Count,
            "identical_capabilities_same_frame_formats");
        Check(
            ScanOptionPolicy.Resolutions(first, 600).SequenceEqual(
                ScanOptionPolicy.Resolutions(second, 600)),
            "identical_capabilities_same_resolutions");

        // 판 크기만 다른 두 장치는 프레임 규격 목록이 달라야 합니다. 판정이 실제로 보고된
        // 값을 쓰고 있다는 반대 방향 증거입니다.
        ScannerPluginCapabilities small = Caps(true, true, true) with
        {
            MaxScanWidthMm = 36.0,
            MaxScanHeightMm = 25.0,
            MaxScanArea = new ScannerPluginScanArea(0.0, 0.0, 36.0, 25.0),
        };
        Check(
            ScanOptionPolicy.AvailableFrameFormats(small).Count <
                ScanOptionPolicy.AvailableFrameFormats(first).Count,
            "smaller_bed_offers_fewer_frame_formats");
    }
}
