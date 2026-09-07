using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>DevelopInspectorResetterTests</c> · <c>DevelopResetUndoTests</c>.
/// 신쇄 <see cref="DevelopPanelState.ResetAllAdjustments"/>.
/// </summary>
internal static class DevelopInspectorResetterTests
{
    public static void Run()
    {
        string isolatedBase = Path.Combine(
            Path.Combine(AppContext.BaseDirectory, "develop-reset-tests"),
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        NegativeLimits negativeLimits = new(MinimumManualDmin: 0.001f, MaximumManualDmin: 1.0f);
        ToneLimits limits = new(
            MaximumExposureStops: 5.0f,
            MaximumToneControl: 1.0f,
            MaximumEndpointToneControl: 2.0f,
            MinimumFilmEmulationIntensity: 0.0,
            MaximumFilmEmulationIntensity: 1.0);

        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);

            DevelopPanelState panel = new(host, limits, negativeLimits);
            Check(panel.Select("frame-1"), "reset_select");
            Check(panel.SetManualBase(0.3, 0.4, 0.5) == LibraryFrameError.None, "reset_set_base");
            Check(panel.Tone.SetExposure(1.0) == LibraryFrameError.None, "reset_set_exposure");
            Check(
                panel.Color.SetColorModel(new ColorModelRecipe(0.8, 0, 0, 0, 0, 0, 0, 0)) ==
                    LibraryFrameError.None,
                "reset_set_warmth");
            Check(
                panel.SetNoiseReduction(new NoiseReductionRecipe(0.9, 0.5, 0.5, 0.5, 0.5, 0.0)) ==
                    LibraryFrameError.None,
                "reset_set_nr");
            Check(panel.SetStraightenAngle(3.5) == LibraryFrameError.None, "reset_set_angle");

            Check(panel.ResetAllAdjustments() == LibraryFrameError.None, "reset_all_ok");
            Check(panel.Tone.Exposure == 0 && panel.Tone.Contrast == 0, "reset_all_clears_tone");
            Check(panel.Color.ColorModel == ColorModelRecipe.Identity, "reset_all_clears_color");
            Check(
                panel.NoiseReduction == NoiseReductionRecipe.Identity,
                "reset_all_clears_nr");
            Check(panel.SelectedFrame!.LookPresetId is null, "reset_all_clears_look");
            Check(
                panel.ManualBase is { Red: 0.3, Green: 0.4, Blue: 0.5 },
                "reset_all_preserves_manual_base");
            Check(panel.SelectedFrame.ImageTransform.StraightenAngle == 3.5, "reset_all_preserves_geometry");
            Check(host.CanUndo, "reset_all_is_undoable");
            Check(
                host.UndoActionName == LibraryHostService.UndoActions.ResetAdjustments,
                "reset_all_undo_name");

            Check(host.Undo() == LibraryHostService.UndoActions.ResetAdjustments, "reset_undo");
            Check(panel.Select("frame-1"), "reset_reselect_after_undo");
            Check(panel.Tone.Exposure == 1.0, "reset_undo_restores_exposure");
            Check(panel.Color.ColorModel.Warmth == 0.8, "reset_undo_restores_warmth");
            Check(panel.NoiseReduction.Strength == 0.9, "reset_undo_restores_nr");
            Check(host.CanRedo, "reset_undo_can_redo");

            Check(host.Redo() == LibraryHostService.UndoActions.ResetAdjustments, "reset_redo");
            Check(panel.Select("frame-1"), "reset_reselect_after_redo");
            Check(panel.Tone.Exposure == 0, "reset_redo_clears_exposure");
            Check(panel.Color.ColorModel == ColorModelRecipe.Identity, "reset_redo_clears_color");

            VerifyNeutralPresetComesBack(panel, host);
            VerifyPhotoAngleReset(panel);
            VerifyBaseScaleContract(panel);
        }
        finally
        {
            if (Directory.Exists(isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// macOS <c>DevelopInspectorResetter</c> 는 <c>.tone</c> 구획 초기화와 모든 보정
    /// 초기화 둘 다에서 <c>frame.preset = neutralPreset</c> 을 놓습니다
    /// (<c>DevelopWorkflowInspector.neutralPreset</c> = 목록의 "neutral").
    /// </summary>
    private static void VerifyNeutralPresetComesBack(
        DevelopPanelState panel,
        LibraryHostService host)
    {
        IReadOnlyList<LookPreset> saved = LookPresetLibrary.All;
        try
        {
            LookPresetLibrary.SetForTests([
                new LookPreset(
                    "neutral",
                    "Neutral",
                    1,
                    [FilmType.ColorNegative],
                    new LookPresetTone(0, 0, 0, 0, 0, null),
                    new LookPresetColor(0, 0, 0, 0),
                    new LookPresetTexture(0, 0, 0)),
            ]);

            Check(PickLook(panel, host, "rich-neutral"), "reset_neutral_pick_other_look");
            Check(panel.ResetAllAdjustments() == LibraryFrameError.None, "reset_neutral_all_ok");
            Check(
                panel.SelectedFrame!.LookPresetId == "neutral",
                "reset_all_restores_neutral_look");

            Check(PickLook(panel, host, "rich-neutral"), "reset_neutral_pick_look_again");
            Check(panel.Tone.ResetBasicTone() == LibraryFrameError.None, "reset_neutral_tone_ok");
            Check(
                panel.SelectedFrame!.LookPresetId == "neutral",
                "reset_tone_restores_neutral_look");
        }
        finally
        {
            LookPresetLibrary.SetForTests(saved);
        }
    }

    /// <summary>
    /// macOS <c>resetPhotoAngle</c> 은 회전과 수평 보정만 0 으로 돌리고 크롭·뒤집기는
    /// 그대로 둡니다. 잠금은 <c>canResetPhotoAngle</c>(회전≠0 또는 |각도| ≥ 1e-4)입니다.
    /// </summary>
    private static void VerifyPhotoAngleReset(DevelopPanelState panel)
    {
        Check(panel.SetStraightenAngle(0) == LibraryFrameError.None, "reset_angle_clear");
        Check(!panel.CanResetPhotoAngle, "reset_angle_locked_when_identity");

        Check(panel.SetStraightenAngle(1e-4) == LibraryFrameError.None, "reset_angle_threshold");
        Check(panel.CanResetPhotoAngle, "reset_angle_open_at_threshold");

        Check(
            panel.SetCrop(new ImageCropRect(0.1, 0.1, 0.8, 0.8)) == LibraryFrameError.None,
            "reset_angle_set_crop");
        Check(panel.SetStraightenAngle(3.5) == LibraryFrameError.None, "reset_angle_set_angle");
        Check(panel.Rotate(clockwise: true) == LibraryFrameError.None, "reset_angle_rotate");

        Check(panel.ResetPhotoAngle() == LibraryFrameError.None, "reset_angle_ok");
        Check(
            panel.SelectedFrame!.ImageTransform.Rotation == ImageRotation.Degrees0 &&
            panel.SelectedFrame.ImageTransform.StraightenAngle == 0,
            "reset_angle_clears_rotation_and_straighten");
        Check(
            panel.SelectedFrame.ImageTransform.Crop is { Width: 0.8 },
            "reset_angle_keeps_crop");
        Check(!panel.CanResetPhotoAngle, "reset_angle_locked_after_reset");
    }

    /// <summary>
    /// 베이스 배율의 계약입니다 — <b>자동에서만·[0.5, 1.5]·비누적·전체 초기화는 100%</b>
    /// (W28·W29·W56).
    /// </summary>
    /// <remarks>
    /// <para>
    /// 배율은 잰 base 에 곱하는 값이라 <b>쌓이면 안 됩니다.</b> 같은 값을 두 번 넣었을 때
    /// 곱해지면 사용자가 슬라이더를 놓을 때마다 그림이 계속 어두워집니다.
    /// </para>
    /// <para>
    /// 수동 base 에서는 아예 받지 않습니다 — 손으로 찍은 값에 배율을 곱하면 사용자가 찍은
    /// 그 자리가 아니게 됩니다. macOS 도 자동일 때만 이 줄을 보여 줍니다.
    /// </para>
    /// <para>
    /// 배율만 바꾸는 편집은 잰 base(<c>ManualBase</c>)를 지우지 않아야 합니다. 지우면
    /// 배율을 만질 때마다 base 를 다시 재게 되어, 같은 사진에서 값이 흔들립니다.
    /// </para>
    /// </remarks>
    private static void VerifyBaseScaleContract(DevelopPanelState panel)
    {
        // 앞 시험이 base 를 수동으로 남겨 두므로 자동으로 돌려놓고 시작합니다 - 배율은
        // 자동에서만 받습니다.
        Check(panel.SetBaseMode(BaseEstimationMode.Auto) == LibraryFrameError.None,
            "scale_needs_auto_base");
        Check(panel.SelectedFrame!.Base.Mode == BaseEstimationMode.Auto, "scale_base_is_auto");

        foreach (double scale in new[] { 0.5, 0.75, 1.0, 1.25, 1.5 })
        {
            Check(panel.SetBaseScale(scale) == LibraryFrameError.None, $"scale_accepts_{scale}");
            Check(panel.BaseScale == scale, $"scale_stores_{scale}", () => panel.BaseScale.ToString());
            // **비누적** — 같은 값을 다시 넣어도 곱해지지 않습니다.
            Check(panel.SetBaseScale(scale) == LibraryFrameError.None, $"scale_repeat_{scale}");
            Check(panel.BaseScale == scale, $"scale_does_not_accumulate_{scale}",
                () => panel.BaseScale.ToString());
        }

        Check(panel.SetBaseScale(1.25) == LibraryFrameError.None, "scale_set_before_range_checks");
        foreach (double outside in new[] { 0.49, 1.51, double.NaN, double.PositiveInfinity })
        {
            Check(panel.SetBaseScale(outside) == LibraryFrameError.InvalidBaseRecipe,
                $"scale_refuses_{outside}");
            Check(panel.BaseScale == 1.25, $"scale_keeps_value_after_refusing_{outside}",
                () => panel.BaseScale.ToString());
        }

        // 잰 base 는 배율 편집으로 사라지지 않습니다.
        Check(panel.SetPickedBase(0.31, 0.42, 0.53) == LibraryFrameError.None, "scale_pick_base");
        Check(panel.SelectedFrame!.Base.Mode == BaseEstimationMode.Manual, "scale_pick_switches_to_manual");
        Check(panel.SetBaseScale(1.25) == LibraryFrameError.InvalidBaseRecipe,
            "scale_refused_while_base_is_manual");

        Check(panel.ResetAllAdjustments() == LibraryFrameError.None, "scale_reset_all_ok");
        Check(panel.BaseScale == 1.0, "scale_reset_all_returns_to_100",
            () => panel.BaseScale.ToString());
    }

    private static bool PickLook(DevelopPanelState panel, LibraryHostService host, string id)
    {
        LibraryFrameSnapshot frame = panel.SelectedFrame!;
        bool ok = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                LookPreset: new LookPresetSelection(id))) == LibraryFrameError.None;
        return ok && panel.Select(frame.Id) && panel.SelectedFrame!.LookPresetId == id;
    }
}
