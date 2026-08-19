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
