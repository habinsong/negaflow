namespace Negaflow.Catalog;

/// <summary>
/// 현상 설정 붙여넣기 범위입니다. macOS <c>DevelopSettingsPasteScope</c> 와 같은 다섯 묶음이며
/// 묶음에 무엇이 들어가는지도 같습니다.
/// </summary>
/// <remarks>
/// <see langword="default"/> 는 다섯 개가 모두 꺼진 <see cref="Empty"/> 입니다. macOS 의 인자 없는
/// 생성자는 전부 켜진 값이므로, 이쪽에서 "기본값"을 원할 때는 <see cref="All"/> 를 쓰십시오.
/// </remarks>
/// <param name="BaseRgb">
/// 잰 <b>Dmin 값 자체</b>를 옮깁니다. <see cref="Base"/> 가 "어떻게 잴지" 를 옮기는 것과
/// 다릅니다 — 이쪽은 붙여넣는 쪽을 <b>수동</b> 으로 바꾸고 그 RGB 를 채웁니다.
/// </param>
/// <remarks>
/// 한 컷에서 베이스를 제대로 잡아 두고 같은 롤의 나머지에 그 값을 그대로 물리는 것이 이
/// 묶음의 용도입니다. <see cref="Base"/> 만으로는 "자동" 이라는 <i>모드</i>가 따라갈 뿐이라
/// 받는 쪽이 자기 사진에서 다시 재고, 리베이트가 얇거나 없으면 컷마다 다른 값이 나옵니다.
/// </remarks>
public readonly record struct DevelopSettingsPasteScope(
    bool Base,
    bool Tone,
    bool Color,
    bool Detail,
    bool Geometry,
    bool BaseRgb = false)
{
    public static DevelopSettingsPasteScope All { get; } = new(true, true, true, true, true, true);

    /// <summary>사용자 프리셋이 담고 푸는 범위입니다 — <see cref="BaseRgb"/> 만 뺍니다.</summary>
    /// <remarks>
    /// 프리셋은 여러 사진에 다시 쓰라고 만드는 것입니다. 한 컷에서 잰 Dmin 을 그 안에 구워
    /// 넣으면, 그 프리셋을 쓰는 모든 사진이 남의 필름 베이스로 현상됩니다. 베이스 값은
    /// 사진마다 다르므로 프리셋이 아니라 붙여넣기로 옮길 것입니다.
    /// </remarks>
    public static DevelopSettingsPasteScope Preset { get; } =
        All with { BaseRgb = false };

    public static DevelopSettingsPasteScope Empty => default;

    public bool IsEmpty => !Base && !Tone && !Color && !Detail && !Geometry && !BaseRgb;

    public bool IsFullDevelopScope =>
        Base && Tone && Color && Detail && Geometry && BaseRgb;

    /// <summary>
    /// <paramref name="source"/> 에서 고른 묶음만 <paramref name="destination"/> 위에 옮긴 사본입니다.
    /// 두 입력 모두 그대로 둡니다.
    /// </summary>
    /// <remarks>
    /// 옮기지 않는 것이 둘 있습니다. 파일 출처(<c>SourceTransport</c>, 원본 메타데이터, 별점 같은
    /// frame 자체의 성질)와 <c>DefectRecipe</c> 입니다. 결함 편집은 그 이미지의 좌표와
    /// 원본 해시에 묶여 있어서 다른 frame 에 옮기면 엉뚱한 자리를 지우거나 요청 자체가 거부됩니다.
    /// macOS 도 결함 편집은 frame sidecar 에 두고 붙여넣기에 싣지 않습니다.
    /// </remarks>
    public LibraryFrameSnapshot Apply(
        LibraryFrameSnapshot source,
        LibraryFrameSnapshot destination)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(destination);
        if (IsEmpty)
        {
            return destination;
        }

        LibraryFrameSnapshot next = destination;
        DevelopRouteSnapshot route = destination.Route;

        if (Base)
        {
            // SourceTransport 와 legacy 표시는 그 파일을 어떻게 읽었는지의 기록이라 설정이
            // 아닙니다. 옮기면 붙여넣기가 출처를 위조하게 됩니다.
            route = route with
            {
                FilmType = source.Route.FilmType,
                SourceSignalKind = source.Route.SourceSignalKind,
                DevelopmentProcess = source.Route.DevelopmentProcess,
            };
            next = next with
            {
                Base = source.Base,
                ManualBase = source.ManualBase,
                AutoLevels = source.AutoLevels,
                AutoNeutralBalance = source.AutoNeutralBalance,
                DevelopTarget = source.DevelopTarget,
            };
        }

        if (Tone)
        {
            // 프리셋은 톤의 바탕이므로 톤과 함께 움직입니다. 델타만 옮기면 같은 값인데 다른
            // 그림이 나옵니다.
            next = next with
            {
                Tone = source.Tone,
                PointCurves = source.PointCurves,
                LookPresetId = source.LookPresetId,
            };
        }

        if (Color)
        {
            route = route with
            {
                FilmEmulation = source.Route.FilmEmulation,
                FilmEmulationIntensity = source.Route.FilmEmulationIntensity,
            };
            next = next with
            {
                ColorModel = source.ColorModel,
                ColorMixer = source.ColorMixer,
                ColorGrading = source.ColorGrading,
                PrimaryCalibration = source.PrimaryCalibration,
                BwToning = source.BwToning,
            };
        }

        if (Detail)
        {
            next = next with
            {
                Texture = source.Texture,
                NoiseReduction = source.NoiseReduction,
                LocalDodgeBurn = source.LocalDodgeBurn,
                DefectRemovalStrength = source.DefectRemovalStrength,
            };
        }

        if (Geometry)
        {
            next = next with { ImageTransform = source.ImageTransform };
        }

        // 잰 값 자체를 옮깁니다. 자동으로 잰 것이든 손으로 찍은 것이든 마지막 현상이 실제로
        // 쓴 Dmin 이 `AppliedBase` 에 남으므로 그것을 먼저 봅니다 - 그래야 "자동이 잘 잡힌 한
        // 컷" 의 값을 나머지에 물릴 수 있습니다. 아직 한 번도 현상되지 않아 그 자리가 비어
        // 있으면 손으로 찍어 둔 표본으로 갑니다.
        //
        // 값이 없으면 모드도 바꾸지 않습니다. 채울 것이 없는데 수동으로 돌리면 받는 쪽이
        // 현상 불가가 되어 화면이 빕니다.
        if (BaseRgb && (source.AppliedBase ?? source.ManualBase) is { } sampled)
        {
            next = next with
            {
                ManualBase = sampled,
                Base = next.Base with { Mode = BaseEstimationMode.Manual },
            };
        }

        return ReferenceEquals(route, destination.Route) ? next : next with { Route = route };
    }
}
