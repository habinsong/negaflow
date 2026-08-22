using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 단추나 단축키로 프레임을 놓을 때 어디에 놓을지, 그리고 손으로 그린 사각형을 규격 비율로
/// 되돌리는 규칙입니다. macOS <c>FlatbedScanRegionLayout</c> 을 그대로 옮긴 것입니다.
/// </summary>
/// <remarks>
/// 규격 치수(mm)는 스트립을 가로로 놓았을 때 기준이라 그대로 쓰면 필름을 세로로 얹은
/// 평판에서 항상 90도 틀어진 프레임이 나옵니다. 홀더는 프레임이 가장 많이 들어가는 방향,
/// 즉 스캔 영역의 긴 축을 따라 놓이므로 프레임 진행 축도 그 축을 따릅니다. 이미 놓인
/// 프레임이 있으면 그 방향과 크기를 이어받아 다음 칸에 붙입니다.
/// </remarks>
public static class FlatbedScanRegionLayout
{
    /// <summary>프레임 사이 간격의 공칭값입니다. 35mm 필름의 프레임 간격이 대략 이 정도입니다.</summary>
    public const double FrameGapMm = 2.0;

    /// <summary>방향키 한 번의 이동 거리입니다. 미세 조정이라 필름 한 칸 간격보다 훨씬 작습니다.</summary>
    public const double NudgeStepMm = 0.5;

    /// <summary>프레임 하나의 최소 크기입니다. 이보다 작으면 집을 수 없습니다.</summary>
    public const double MinimumUnitExtent = 0.005;

    /// <summary>
    /// 다음 프레임을 놓을 자리입니다. <paramref name="overrideSize"/> 를 주면 규격 대신 그
    /// 크기로 놓습니다(복사한 프레임 붙여넣기).
    /// </summary>
    public static FlatbedScanRegion? ProposedRect(
        IReadOnlyList<FlatbedScanRegion> existing,
        FlatbedFrameFormat frameFormat,
        FlatbedPreviewArea previewArea,
        (double Width, double Height)? overrideSize = null)
    {
        ArgumentNullException.ThrowIfNull(existing);
        if (!previewArea.IsValid)
        {
            return null;
        }
        double gapX = FrameGapMm / previewArea.WidthMm;
        double gapY = FrameGapMm / previewArea.HeightMm;
        if (existing.Count == 0)
        {
            (double firstWidth, double firstHeight) =
                overrideSize ?? FirstFrameSize(frameFormat, previewArea);
            return Centered(firstWidth, firstHeight);
        }

        FlatbedScanRegion last = existing[^1];
        FlatbedScanRegion first = existing[0];
        (double sizeWidth, double sizeHeight) =
            overrideSize ?? (last.UnitWidth, last.UnitHeight);
        // 프레임의 긴 축(mm)이 스트립 진행 축입니다. 정사각 프레임은 가로로 진행시킵니다.
        bool advancesAlongX =
            last.UnitWidth * previewArea.WidthMm >= last.UnitHeight * previewArea.HeightMm;
        (double X, double Y) next = advancesAlongX
            ? (last.UnitMaxX + gapX, last.UnitY)
            : (last.UnitX, last.UnitMaxY + gapY);
        if (Fits(next.X, next.Y, sizeWidth, sizeHeight))
        {
            return FlatbedScanRegion.Create(next.X, next.Y, sizeWidth, sizeHeight);
        }

        // 스트립 끝입니다. 다음 줄 첫 칸(첫 프레임의 진행축 위치)으로 넘어갑니다.
        (double X, double Y) wrapped = advancesAlongX
            ? (first.UnitX, last.UnitMaxY + gapY)
            : (last.UnitMaxX + gapX, first.UnitY);
        return Fits(wrapped.X, wrapped.Y, sizeWidth, sizeHeight)
            ? FlatbedScanRegion.Create(wrapped.X, wrapped.Y, sizeWidth, sizeHeight)
            : Centered(sizeWidth, sizeHeight);
    }

    /// <summary>
    /// 방향키 한 번이 움직일 거리를 프리뷰 기준 비율로 바꿉니다. Shift 는 필름 한 칸
    /// 간격만큼 크게 밉니다.
    /// </summary>
    public static (double X, double Y) NudgeStep(FlatbedPreviewArea previewArea, bool coarse)
    {
        double distanceMm = coarse ? FrameGapMm : NudgeStepMm;
        if (!previewArea.IsValid)
        {
            // 프리뷰 영역을 모르면 물리 거리로 환산할 수 없습니다. 눈에 보이는 최소 단위로 밉니다.
            return (0.002, 0.002);
        }
        return (distanceMm / previewArea.WidthMm, distanceMm / previewArea.HeightMm);
    }

    /// <summary>
    /// 손으로 그리거나 핸들로 조정한 사각형을 선택한 규격의 비율에 맞춥니다. 눈으로는 6x7
    /// 인지 6x9 인지 구분할 수 없으므로, 크기를 바꾸는 조작마다 비율을 규격으로 되돌립니다.
    /// </summary>
    /// <remarks>
    /// 비율은 화면 픽셀이 아니라 물리 치수(mm)로 따집니다. 방향은 사용자가 그린 형태에
    /// 가까운 쪽(가로/세로)을 쓰고, 움직이지 않은 변은 그대로 두며, 조작하지 않은 축은
    /// 중심을 지킵니다.
    /// </remarks>
    public static FlatbedScanRegion SnappedToFrameAspect(
        FlatbedScanRegion rect,
        FlatbedScanRegion anchoredTo,
        FlatbedFrameFormat frameFormat,
        FlatbedPreviewArea previewArea,
        double epsilon = 0.000_1)
    {
        ArgumentNullException.ThrowIfNull(rect);
        ArgumentNullException.ThrowIfNull(anchoredTo);
        if (!previewArea.IsValid || rect.UnitWidth <= 0 || rect.UnitHeight <= 0)
        {
            return rect;
        }
        bool movedX = Math.Abs(rect.UnitX - anchoredTo.UnitX) > epsilon ||
            Math.Abs(rect.UnitMaxX - anchoredTo.UnitMaxX) > epsilon;
        bool movedY = Math.Abs(rect.UnitY - anchoredTo.UnitY) > epsilon ||
            Math.Abs(rect.UnitMaxY - anchoredTo.UnitMaxY) > epsilon;
        // 크기를 건드리지 않은 조작(이동)은 비율에 손대지 않습니다.
        if (!movedX && !movedY)
        {
            return rect;
        }

        double widthMm = rect.UnitWidth * previewArea.WidthMm;
        double heightMm = rect.UnitHeight * previewArea.HeightMm;
        double aspect = widthMm / heightMm;
        if (!double.IsFinite(aspect) || aspect <= 0)
        {
            return rect;
        }
        double target = NearestAspect(frameFormat, aspect);
        double aspectWidth = heightMm * target / previewArea.WidthMm;
        double aspectHeight = widthMm / target / previewArea.HeightMm;

        double sizeWidth;
        double sizeHeight;
        if (movedX != movedY)
        {
            // 한 변만 끈 경우: 끈 축이 크기를 정하고 반대 축이 따라옵니다.
            (sizeWidth, sizeHeight) = movedX
                ? (rect.UnitWidth, aspectHeight)
                : (aspectWidth, rect.UnitHeight);
        }
        else
        {
            // 모서리를 끌거나 새로 그린 경우: 짧은 축에 맞춰 그린 영역 밖으로 커지지 않게 합니다.
            (sizeWidth, sizeHeight) = aspect > target
                ? (aspectWidth, rect.UnitHeight)
                : (rect.UnitWidth, aspectHeight);
        }

        double originX = movedX
            ? AnchoredOrigin(
                rect.UnitX, rect.UnitMaxX, anchoredTo.UnitX, anchoredTo.UnitMaxX,
                sizeWidth, epsilon)
            : ((rect.UnitX + rect.UnitMaxX) / 2) - (sizeWidth / 2);
        double originY = movedY
            ? AnchoredOrigin(
                rect.UnitY, rect.UnitMaxY, anchoredTo.UnitY, anchoredTo.UnitMaxY,
                sizeHeight, epsilon)
            : ((rect.UnitY + rect.UnitMaxY) / 2) - (sizeHeight / 2);
        return (rect with
        {
            UnitX = originX,
            UnitY = originY,
            UnitWidth = sizeWidth,
            UnitHeight = sizeHeight,
        }).Clamped();
    }

    /// <summary>
    /// 규격의 비율 후보입니다. 가로로 놓은 것과 세로로 놓은 것 둘 다이며, 정사각은 하나입니다.
    /// </summary>
    public static IReadOnlyList<double> FrameAspectCandidates(FlatbedFrameFormat format)
    {
        double aspect = FilmFrameFormats.StripWidthMm(format) /
            FilmFrameFormats.StripHeightMm(format);
        double rotated = 1.0 / aspect;
        return Math.Abs(aspect - rotated) < 0.000_001 ? [aspect] : [aspect, rotated];
    }

    private static double NearestAspect(FlatbedFrameFormat format, double aspect)
    {
        double best = aspect;
        double bestDistance = double.PositiveInfinity;
        foreach (double candidate in FrameAspectCandidates(format))
        {
            double distance = Math.Abs(Math.Log(candidate) - Math.Log(aspect));
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = candidate;
            }
        }
        return best;
    }

    /// <summary>움직이지 않은 변을 고정합니다. 양쪽 다 움직였으면 중심을 지킵니다.</summary>
    private static double AnchoredOrigin(
        double minimum,
        double maximum,
        double previousMinimum,
        double previousMaximum,
        double extent,
        double epsilon)
    {
        if (Math.Abs(minimum - previousMinimum) <= epsilon)
        {
            return minimum;
        }
        if (Math.Abs(maximum - previousMaximum) <= epsilon)
        {
            return maximum - extent;
        }
        return ((minimum + maximum) / 2) - (extent / 2);
    }

    private static (double Width, double Height) FirstFrameSize(
        FlatbedFrameFormat frameFormat,
        FlatbedPreviewArea previewArea)
    {
        bool stripAdvancesAlongY = previewArea.HeightMm > previewArea.WidthMm;
        double widthMm = stripAdvancesAlongY
            ? FilmFrameFormats.StripHeightMm(frameFormat)
            : FilmFrameFormats.StripWidthMm(frameFormat);
        double heightMm = stripAdvancesAlongY
            ? FilmFrameFormats.StripWidthMm(frameFormat)
            : FilmFrameFormats.StripHeightMm(frameFormat);
        return (
            Math.Clamp(widthMm / previewArea.WidthMm, 0.02, 1.0),
            Math.Clamp(heightMm / previewArea.HeightMm, 0.02, 1.0));
    }

    private static FlatbedScanRegion Centered(double width, double height) =>
        FlatbedScanRegion.Create((1 - width) / 2, (1 - height) / 2, width, height);

    private static bool Fits(double x, double y, double width, double height) =>
        x >= 0 && y >= 0 && x + width <= 1 && y + height <= 1;
}
