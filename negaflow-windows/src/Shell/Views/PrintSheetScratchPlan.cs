using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 판에 얹을 임시 현상본을 <b>얼마나 크게</b> 만들지 정합니다.
/// </summary>
public static partial class PrintSheetWriter
{
    /// <summary>
    /// 사진마다 임시 현상본의 긴 변입니다. <b>판에 놓일 크기</b>에서 나옵니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 예전에는 사진마다 원본 해상도로 현상해 임시 TIFF 를 쓰고, 판에 얹을 때 그것을 다시
    /// 열어 줄였습니다. 콘택트 시트에서는 한 칸이 354×237 인데 그 한 칸을 채우려고 24MP 를
    /// 통째로 만들고 통째로 디코드했습니다 — 실측으로 얹기 한 번에 220~380 ms, 열두 장이면
    /// 3.3 초였습니다. 여기에 원본 해상도 인코딩과 140MB 짜리 파일 쓰기·읽기가 얹힙니다.
    /// </para>
    /// <para>
    /// macOS 에는 이 자리가 없습니다. <c>PrintPackageRenderer</c> 는 <c>CIImage</c> 로
    /// 합성하므로 현상 사슬과 축소가 하나로 접혀 <b>최종 판 해상도로 한 번만</b> 렌더됩니다.
    /// </para>
    /// <para>
    /// 판은 사진의 <b>가로세로 비율만</b> 봅니다(<c>PrintPackageLayout.Make</c> 는 방향
    /// 비교에만 쓰고, <c>PrintCompositionLayout.Make</c> 는 비율로 칸을 맞춥니다). 그 비율은
    /// 화소를 풀지 않고 구할 수 있습니다 — 원본 크기를 헤더에서 읽고 회전·크롭을 적용하면
    /// 됩니다. 수평 보정은 <b>같은 비율의 내접 크롭</b>이라 비율을 바꾸지 않습니다
    /// (<c>image_transform.h</c>). 그래서 여기서 짠 판은 실제로 나올 판과 같고, 뒤에서
    /// 현상본의 진짜 크기로 다시 짜는 계산도 그대로 둡니다.
    /// </para>
    /// <para>
    /// 하나라도 크기를 못 읽으면 <b>전부 원본 해상도</b>로 갑니다 — 모르는 값으로 그림을
    /// 줄이지 않습니다.
    /// </para>
    /// </remarks>
    private static int[] PlanScratchLongEdges(
        IReadOnlyList<LibraryFrameSnapshot> sources,
        PrintPreferences print)
    {
        int[] none = new int[sources.Count];
        PrintSizeMm[] planned = new PrintSizeMm[sources.Count];
        for (int index = 0; index < sources.Count; ++index)
        {
            if (DevelopedPixelSize(sources[index]) is not { } size)
            {
                return none;
            }
            planned[index] = size;
        }

        PrintCompositionSettings composition = print.Composition(
            planned[0].Height > 0 ? planned[0].Width / planned[0].Height : null);
        double[] longest = new double[sources.Count];
        if (PrintPreferences.PackageModeFor(print.LayoutMode) is not null)
        {
            if (PrintPackageLayout.Make(planned, composition, print.Package())
                is not { Count: > 0 } pages)
            {
                return none;
            }
            foreach (PrintPackagePageLayout page in pages)
            {
                foreach (PrintPackageItemLayout item in page.Items)
                {
                    longest[item.SourceIndex] = Math.Max(
                        longest[item.SourceIndex],
                        Math.Max(item.ImageRect.Width, item.ImageRect.Height));
                }
            }
        }
        else
        {
            for (int index = 0; index < planned.Length; ++index)
            {
                PrintCompositionSettings pageSettings = composition with
                {
                    PhotoAspectRatio = planned[index].Height > 0
                        ? planned[index].Width / planned[index].Height
                        : null,
                };
                if (PrintCompositionLayout.Make(planned[index], pageSettings) is not { } layout)
                {
                    return none;
                }
                longest[index] = Math.Max(layout.ImageRect.Width, layout.ImageRect.Height);
            }
        }

        int[] result = new int[sources.Count];
        for (int index = 0; index < result.Length; ++index)
        {
            double source = Math.Max(planned[index].Width, planned[index].Height);
            // 여유를 둡니다. 뒤에서 진짜 현상본 크기로 판을 다시 짜므로 몇 화소가 어긋나도
            // 얹을 때 늘려 쓰는 일이 없어야 합니다.
            double wanted = Math.Ceiling(longest[index] * ScratchLongEdgeMargin);
            // 원본보다 크게 잡지 않습니다 — 상한은 줄이기 위한 것이지 늘리기 위한 것이 아닙니다.
            result[index] = wanted >= source || wanted < 1.0 ? 0 : (int)wanted;
        }
        return result;
    }

    /// <summary>얹을 자리보다 이만큼 크게 현상합니다.</summary>
    private const double ScratchLongEdgeMargin = 1.25;

    private static bool TryProbe(
        string sourcePath,
        out uint pixelWidth,
        out uint pixelHeight,
        out uint orientation)
    {
        pixelWidth = 0U;
        pixelHeight = 0U;
        orientation = 1U;
        try
        {
            if (NativeStandardImageSourceProbe.TryRead(sourcePath, out var standard) &&
                standard.PixelWidth > 0U && standard.PixelHeight > 0U)
            {
                pixelWidth = standard.PixelWidth;
                pixelHeight = standard.PixelHeight;
                orientation = standard.Orientation;
                return true;
            }
            if (NativeTiffSourceProbe.TryRead(sourcePath, out var tiff) &&
                tiff.PixelWidth > 0U && tiff.PixelHeight > 0U)
            {
                pixelWidth = tiff.PixelWidth;
                pixelHeight = tiff.PixelHeight;
                orientation = tiff.Orientation;
                return true;
            }
        }
        catch (NativeBootstrapException)
        {
            // 엔진을 못 부르면 상한 없이 갑니다 — 진단 하나 때문에 인화를 세우지 않습니다.
        }
        return false;
    }

    /// <summary>
    /// 현상하면 나올 화소 크기입니다. <b>화소를 풀지 않습니다</b> — 원본 헤더에서 크기를 읽고
    /// 회전과 크롭만 적용합니다.
    /// </summary>
    private static PrintSizeMm? DevelopedPixelSize(LibraryFrameSnapshot frame)
    {
        // 두 프로브의 받는 조건이 다릅니다 — 표준 이미지 쪽은 16bit RGBA 로 풀리는 것만 받고,
        // TIFF 쪽은 스캐너가 내는 8/16bit 흑백·RGB 도 받습니다. 어느 쪽이든 되는 것을 씁니다.
        if (!TryProbe(frame.SourcePath, out uint pixelWidth, out uint pixelHeight,
                out uint orientation))
        {
            return null;
        }
        double width = pixelWidth;
        double height = pixelHeight;
        // EXIF/TIFF 방향 5~8 은 가로세로가 바뀐 채로 저장된 것입니다.
        if (orientation is >= 5 and <= 8)
        {
            (width, height) = (height, width);
        }
        if (frame.ImageTransform.Crop is { } crop)
        {
            width *= crop.Width;
            height *= crop.Height;
        }
        if (frame.ImageTransform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270)
        {
            (width, height) = (height, width);
        }
        return width >= 1.0 && height >= 1.0 ? new PrintSizeMm(width, height) : null;
    }

}
