namespace Negaflow.Catalog;

/// <summary>
/// 현상 설정 붙여넣기 범위입니다. macOS <c>DevelopSettingsPasteScope</c> 와 같은 일곱 묶음이며
/// 묶음에 무엇이 들어가는지도 같습니다.
/// </summary>
/// <remarks>
/// <see langword="default"/> 는 모두 꺼진 <see cref="Empty"/> 입니다. macOS 의 인자 없는
/// 생성자는 전부 켜진 값이므로, 이쪽에서 "기본값"을 원할 때는 <see cref="All"/> 를 쓰십시오.
/// </remarks>
public readonly record struct DevelopSettingsPasteScope(
    bool Base,
    bool Tone,
    bool Color,
    bool Detail,
    bool Geometry,
    bool InputGamma,
    bool BaseScale)
{
    public DevelopSettingsPasteScope(bool Base, bool Tone, bool Color, bool Detail, bool Geometry)
        : this(Base, Tone, Color, Detail, Geometry, InputGamma: Base, BaseScale: Base) { }

    public static DevelopSettingsPasteScope All { get; } = new(true, true, true, true, true, true, true);

    public static DevelopSettingsPasteScope Empty => default;

    public bool IsEmpty => !Base && !Tone && !Color && !Detail && !Geometry && !InputGamma && !BaseScale;

    public bool IsFullDevelopScope => Base && Tone && Color && Detail && Geometry && InputGamma && BaseScale;

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

        // 룩 하나가 톤·색·질감에 걸쳐 있으므로 일부만 옮길 때는 실제 적용값으로 풀어 교체한다.
        // 원본과 대상의 룩을 함께 남기면 선택하지 않은 묶음까지 바뀌거나 두 번 더해진다.
        if ((Tone || Color || Detail) && !(Tone && Color && Detail))
        {
            source = LookPresetComposition.Materialize(source);
            destination = LookPresetComposition.Materialize(destination);
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
                Base = source.Base with { Scale = destination.Base.Scale },
                ManualBase = source.ManualBase,
                AutoLevels = source.AutoLevels,
                AutoBalance = source.AutoBalance,
                AutoNeutralBalance = source.AutoNeutralBalance,
                DevelopTarget = source.DevelopTarget,
                ChannelRange = source.ChannelRange,
            };
        }

        if (InputGamma) { next = next with { InputGamma = source.InputGamma }; }
        if (BaseScale) { next = next with { Base = next.Base with { Scale = source.Base.Scale } }; }

        if (Tone)
        {
            // 세 룩 묶음을 모두 옮기면 원본의 프리셋과 델타를 함께 교체한다. 부분 범위는 위에서 풀었다.
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

        return ReferenceEquals(route, destination.Route) ? next : next with { Route = route };
    }
}
