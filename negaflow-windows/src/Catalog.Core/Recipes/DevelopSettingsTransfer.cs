using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 현상 설정 복사/붙여넣기를 catalog record 에 적용합니다. macOS
/// <c>AppModel.pasteDevelopSettings</c> 가 하는 일이며, 셸이 두 writer 의 호출 순서를 몰라도
/// 되도록 여기서 묶습니다.
/// </summary>
public static class DevelopSettingsTransfer
{
    /// <summary>
    /// <paramref name="destinationRecord"/> 의 사본에 범위만큼 붙여넣습니다. route 와 recipe 는
    /// 서로 다른 writer 가 소유하므로 둘 다 지나가며, 어느 쪽이 거절하면 아무것도 쓰지 않은
    /// 실패를 돌려줍니다 — 반쯤 붙은 frame 을 남기지 않습니다.
    /// </summary>
    public static LibraryFrameWriteResult Paste(
        JsonObject destinationRecord,
        LibraryFrameSnapshot source,
        LibraryFrameSnapshot destination,
        DevelopSettingsPasteScope scope)
    {
        ArgumentNullException.ThrowIfNull(destinationRecord);
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(destination);

        if (scope.IsEmpty)
        {
            return LibraryFrameWriteResult.Success(destinationRecord.DeepClone().AsObject());
        }

        LibraryFrameSnapshot merged = scope.Apply(source, destination);
        JsonObject working = destinationRecord;

        // route 는 base 와 color 두 묶음에 걸쳐 있습니다. 둘 다 꺼져 있으면 손대지 않습니다.
        if (scope.Base || scope.Color)
        {
            DevelopRouteWriteResult routeWrite = DevelopRouteWriter.Apply(
                working,
                new DevelopRouteSelection(
                    merged.Route.SourceSignalKind,
                    merged.Route.FilmType,
                    merged.Route.FilmEmulation,
                    merged.Route.FilmEmulationIntensity));
            if (routeWrite.FrameRecord is not { } routedRecord)
            {
                return LibraryFrameWriteResult.Failure(MapRouteError(routeWrite.Error));
            }
            working = routedRecord;
        }

        return LibraryFrameWriter.Apply(
            working,
            new LibraryFrameEdit(
                merged.Tone,
                merged.ManualBase,
                Base: merged.Base,
                PointCurves: merged.PointCurves,
                ColorMixer: merged.ColorMixer,
                ColorGrading: merged.ColorGrading,
                PrimaryCalibration: merged.PrimaryCalibration,
                LocalDodgeBurn: merged.LocalDodgeBurn,
                ColorModel: merged.ColorModel,
                AutoLevels: merged.AutoLevels,
                AutoNeutralBalance: merged.AutoNeutralBalance,
                DevelopTarget: merged.DevelopTarget,
                ImageTransform: merged.ImageTransform,
                Texture: merged.Texture,
                NoiseReduction: merged.NoiseReduction,
                BwToning: merged.BwToning,
                DefectRemovalStrength: merged.DefectRemovalStrength,
                LookPreset: new LookPresetSelection(merged.LookPresetId)));
    }

    /// <summary>
    /// route 쪽 거절 사유를 frame 쪽 이름으로 옮깁니다. 셸은 한 종류의 오류만 다루면 됩니다.
    /// </summary>
    private static LibraryFrameError MapRouteError(DevelopRouteError error) => error switch
    {
        DevelopRouteError.ParametersNotObject => LibraryFrameError.MissingParameters,
        _ => LibraryFrameError.InvalidDevelopRoute,
    };
}
