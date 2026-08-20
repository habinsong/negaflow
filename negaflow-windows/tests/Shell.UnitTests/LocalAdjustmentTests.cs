using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>LocalAdjustmentSession</c>·<c>AppModel+LocalAdjustments</c>·
/// <c>LocalAdjustmentMaskSupport</c> 를 옮긴 규칙입니다.
/// </summary>
internal static class LocalAdjustmentTests
{
    private const string FrameId = "frame-1";

    public static void Run()
    {
        VerifySessionDefaults();
        VerifyDrawingToggle();
        VerifyCopyAndPaste();
        VerifyListEditing();
        VerifyNormalizedFeather();
        VerifyMaskFactory();
        VerifyDraft();
    }

    /// <summary>
    /// macOS <c>LocalAdjustmentMaskFactory</c> — 점이 모자라면 아무 것도 만들지 않고,
    /// 브러시 굵기는 0.005...0.25 로, 페더는 브러시만 0.25 배로 들어갑니다.
    /// </summary>
    private static void VerifyMaskFactory()
    {
        LocalDodgeBurnPoint a = new(0.2, 0.2);
        LocalDodgeBurnPoint b = new(0.6, 0.6);

        Check(
            LocalAdjustmentMaskFactory.Make(LocalDodgeBurnMaskKind.Brush, [], 0.04, 0.5) is null,
            "mask_brush_needs_a_point");
        LocalDodgeBurnMask? brush = LocalAdjustmentMaskFactory.Make(
            LocalDodgeBurnMaskKind.Brush, [a, b], 4.0, 0.5);
        Check(
            brush is not null &&
            brush.Strokes.Count == 1 &&
            brush.Strokes[0].Points.Count == 2 &&
            Math.Abs(brush.Strokes[0].Thickness - 0.25) < 1e-9 &&
            Math.Abs(brush.Strokes[0].Feather - 0.125) < 1e-9,
            "mask_brush_clamps_thickness_and_scales_feather");

        Check(
            LocalAdjustmentMaskFactory.Make(LocalDodgeBurnMaskKind.Radial, [a], 0.04, 0.5) is null,
            "mask_radial_needs_two_points");
        LocalDodgeBurnMask? radial = LocalAdjustmentMaskFactory.Make(
            LocalDodgeBurnMaskKind.Radial, [a, b], 0.04, 0.5);
        Check(
            radial is not null &&
            radial.Center == a &&
            radial.Radius > 0.005,
            "mask_radial_centres_on_the_first_point");
        // 원본 크기를 주면 짧은 변으로 나눈 사진 기준 반지름입니다.
        LocalDodgeBurnMask? sized = LocalAdjustmentMaskFactory.Make(
            LocalDodgeBurnMaskKind.Radial,
            [new LocalDodgeBurnPoint(0.5, 0.5), new LocalDodgeBurnPoint(0.5, 1.0)],
            0.04,
            0.5,
            imageWidth: 200.0,
            imageHeight: 100.0);
        Check(
            sized is not null && Math.Abs(sized.Radius - 0.5) < 1e-9,
            "mask_radial_uses_the_short_edge_when_the_size_is_known");

        Check(
            LocalAdjustmentMaskFactory.Make(
                LocalDodgeBurnMaskKind.Linear, [a, a], 0.04, 0.5) is null,
            "mask_linear_refuses_a_zero_length_drag");
        Check(
            LocalAdjustmentMaskFactory.Make(
                LocalDodgeBurnMaskKind.Linear, [a, b], 0.04, 0.5) is not null,
            "mask_linear_takes_a_real_drag");

        Check(
            LocalAdjustmentMaskFactory.Make(
                LocalDodgeBurnMaskKind.Polygon, [a, b], 0.04, 0.5) is null,
            "mask_polygon_needs_three_points");
        LocalDodgeBurnMask? polygon = LocalAdjustmentMaskFactory.Make(
            LocalDodgeBurnMaskKind.Polygon,
            [a, b, new LocalDodgeBurnPoint(0.2, 0.8)],
            0.04,
            2.0);
        Check(
            polygon is not null && polygon.Points.Count == 3 && polygon.Feather == 1.0,
            "mask_polygon_keeps_points_and_clamps_feather");
    }

    /// <summary>
    /// macOS <c>LocalAdjustmentOverlay</c> 의 끌기 — 브러시는 점을 쌓고, 나머지는 시작점과
    /// 끝점 둘만 씁니다.
    /// </summary>
    private static void VerifyDraft()
    {
        LocalAdjustmentDraft draft = new();
        Check(!draft.IsDragging, "draft_starts_idle");
        Check(
            draft.End(LocalDodgeBurnMaskKind.Brush, new LocalDodgeBurnPoint(0.5, 0.5)).Count == 0,
            "draft_end_without_begin_is_empty");

        draft.Begin(new LocalDodgeBurnPoint(0.1, 0.1));
        draft.Extend(LocalDodgeBurnMaskKind.Brush, new LocalDodgeBurnPoint(0.2, 0.2), stepped: true);
        draft.Extend(LocalDodgeBurnMaskKind.Brush, new LocalDodgeBurnPoint(0.21, 0.21), stepped: false);
        IReadOnlyList<LocalDodgeBurnPoint> brush =
            draft.End(LocalDodgeBurnMaskKind.Brush, new LocalDodgeBurnPoint(0.3, 0.3));
        Check(brush.Count == 3, "draft_brush_keeps_only_stepped_points");
        Check(!draft.IsDragging, "draft_end_clears_the_drag");

        draft.Begin(new LocalDodgeBurnPoint(0.1, 0.1));
        draft.Extend(LocalDodgeBurnMaskKind.Radial, new LocalDodgeBurnPoint(0.2, 0.2), stepped: true);
        draft.Extend(LocalDodgeBurnMaskKind.Radial, new LocalDodgeBurnPoint(0.4, 0.4), stepped: true);
        IReadOnlyList<LocalDodgeBurnPoint> radial =
            draft.End(LocalDodgeBurnMaskKind.Radial, new LocalDodgeBurnPoint(0.9, 0.9));
        Check(
            radial.Count == 2 &&
            radial[0] == new LocalDodgeBurnPoint(0.1, 0.1) &&
            radial[1] == new LocalDodgeBurnPoint(0.9, 0.9),
            "draft_radial_keeps_start_and_end_only");

        draft.Begin(new LocalDodgeBurnPoint(0.1, 0.1));
        draft.Cancel();
        Check(!draft.IsDragging && draft.Points.Count == 0, "draft_cancel_clears_everything");
    }

    /// <summary>macOS 의 초기값 — 양 0.35 · 페더 0.20 · 브러시 굵기 0.04 · 닷지 · 브러시.</summary>
    private static void VerifySessionDefaults()
    {
        LocalAdjustmentSession session = new();
        Check(
            session.Amount == 0.35 &&
            session.Feather == 0.20 &&
            session.BrushThickness == 0.04,
            "local_session_defaults_match_mac");
        Check(
            session.Mode == LocalDodgeBurnMode.Dodge &&
            session.MaskKind == LocalDodgeBurnMaskKind.Brush,
            "local_session_starts_on_dodge_brush");
        Check(session.ActiveFrameId is null, "local_session_starts_inactive");
    }

    /// <summary>
    /// macOS <c>toggleDrawing(_:)</c> — 같은 종류를 다시 누르면 끄고, 다른 종류면 그 종류로
    /// 켜면서 펼쳐 둔 보정을 놓습니다. 종류를 바꾸면 찍어 둔 다각형 꼭짓점도 버립니다.
    /// </summary>
    private static void VerifyDrawingToggle()
    {
        LocalAdjustmentSession session = new();
        IReadOnlyList<LocalDodgeBurnAdjustment> none = [];

        Check(
            session.ToggleDrawing(FrameId, LocalDodgeBurnMaskKind.Radial, none) &&
            session.IsDrawing(FrameId, LocalDodgeBurnMaskKind.Radial),
            "local_toggle_turns_drawing_on");
        Check(
            !session.IsDrawing("other-frame", LocalDodgeBurnMaskKind.Radial),
            "local_drawing_belongs_to_one_frame");
        Check(
            !session.ToggleDrawing(FrameId, LocalDodgeBurnMaskKind.Radial, none) &&
            session.ActiveFrameId is null,
            "local_toggle_turns_drawing_off_when_pressed_again");

        session.MaskKind = LocalDodgeBurnMaskKind.Polygon;
        session.AddPolygonPoint(new LocalDodgeBurnPoint(0.1, 0.1));
        Check(session.PolygonPoints.Count == 1, "local_polygon_point_is_kept");
        session.MaskKind = LocalDodgeBurnMaskKind.Brush;
        Check(
            session.PolygonPoints.Count == 0,
            "local_changing_mask_kind_drops_polygon_points");

        // 켤 때 macOS 는 그 프레임의 마지막 보정을 펼칩니다.
        LocalDodgeBurnAdjustment first = Adjustment(Guid.NewGuid());
        LocalDodgeBurnAdjustment last = Adjustment(Guid.NewGuid());
        session.Activate(FrameId, [first, last]);
        Check(
            session.SelectedAdjustmentId == last.Id,
            "local_activate_selects_the_last_adjustment");
    }

    /// <summary>macOS <c>pastedAdjustment()</c> 는 <b>새 id</b> 를 답니다.</summary>
    private static void VerifyCopyAndPaste()
    {
        LocalAdjustmentSession session = new();
        Check(session.PastedAdjustment() is null, "local_paste_is_empty_before_copy");

        LocalDodgeBurnAdjustment source = Adjustment(Guid.NewGuid());
        session.Copy(source);
        LocalDodgeBurnAdjustment? pasted = session.PastedAdjustment();
        Check(
            pasted is not null && pasted.Id != source.Id,
            "local_paste_gets_a_new_id");
        Check(
            pasted is not null &&
            pasted.Mode == source.Mode &&
            pasted.Amount == source.Amount &&
            pasted.Mask == source.Mask,
            "local_paste_keeps_everything_else");
    }

    private static void VerifyListEditing()
    {
        LocalDodgeBurnAdjustment one = Adjustment(Guid.NewGuid());
        LocalDodgeBurnAdjustment two = Adjustment(Guid.NewGuid());
        IReadOnlyList<LocalDodgeBurnAdjustment> list = LocalAdjustmentEditing.Add([one], two);
        Check(list.Count == 2 && list[1].Id == two.Id, "local_add_appends_to_the_end");

        IReadOnlyList<LocalDodgeBurnAdjustment> toggled = LocalAdjustmentEditing.Update(
            list,
            two.Id,
            current => current with { IsEnabled = !current.IsEnabled });
        Check(
            !toggled[1].IsEnabled && toggled[0].IsEnabled,
            "local_update_touches_only_the_named_one");

        Check(
            ReferenceEquals(LocalAdjustmentEditing.Update(list, Guid.NewGuid(), c => c), list),
            "local_update_of_a_missing_id_changes_nothing");

        IReadOnlyList<LocalDodgeBurnAdjustment> removed = LocalAdjustmentEditing.Remove(list, one.Id);
        Check(removed.Count == 1 && removed[0].Id == two.Id, "local_remove_drops_one");
        Check(
            ReferenceEquals(LocalAdjustmentEditing.Remove(list, Guid.NewGuid()), list),
            "local_remove_of_a_missing_id_changes_nothing");

        Check(
            LocalAdjustmentEditing.RowTitle(0, "브러시") == "1 · 브러시",
            "local_row_title_is_one_based");
    }

    /// <summary>
    /// macOS <c>normalizedFeather</c> — 브러시는 획 페더를 0.25 로 나눈 값이고 나머지는
    /// 마스크 페더를 그대로 씁니다. 되쓸 때 브러시는 <b>모든 획</b>이 같이 바뀝니다.
    /// </summary>
    private static void VerifyNormalizedFeather()
    {
        LocalDodgeBurnStroke[] strokes =
        [
            new([new LocalDodgeBurnPoint(0.1, 0.1)], 0.04, 0.125),
            new([new LocalDodgeBurnPoint(0.2, 0.2)], 0.04, 0.0),
        ];
        LocalDodgeBurnAdjustment brush = new(
            Guid.NewGuid(),
            LocalDodgeBurnMode.Dodge,
            0.5,
            true,
            LocalDodgeBurnMask.Brush(strokes));
        Check(
            Math.Abs(LocalAdjustmentEditing.NormalizedFeather(brush) - 0.5) < 1e-9,
            "local_brush_feather_reads_as_half_of_the_range");

        LocalDodgeBurnAdjustment widened = LocalAdjustmentEditing.WithNormalizedFeather(brush, 1.0);
        Check(
            widened.Mask.Strokes.All(stroke => Math.Abs(stroke.Feather - 0.25) < 1e-9),
            "local_brush_feather_writes_every_stroke");

        LocalDodgeBurnAdjustment radial = new(
            Guid.NewGuid(),
            LocalDodgeBurnMode.Burn,
            0.5,
            true,
            LocalDodgeBurnMask.Radial(new LocalDodgeBurnPoint(0.5, 0.5), 0.3, 0.4));
        Check(
            Math.Abs(LocalAdjustmentEditing.NormalizedFeather(radial) - 0.4) < 1e-9,
            "local_radial_feather_is_used_as_is");
        Check(
            Math.Abs(
                LocalAdjustmentEditing.WithNormalizedFeather(radial, 0.9).Mask.Feather - 0.9) < 1e-9,
            "local_radial_feather_writes_the_mask");
        // 범위를 벗어난 값은 macOS 처럼 0...1 로 자릅니다.
        Check(
            LocalAdjustmentEditing.WithNormalizedFeather(radial, 4.0).Mask.Feather == 1.0,
            "local_feather_is_clamped");
    }

    private static LocalDodgeBurnAdjustment Adjustment(Guid id) => new(
        id,
        LocalDodgeBurnMode.Dodge,
        0.35,
        true,
        LocalDodgeBurnMask.Radial(new LocalDodgeBurnPoint(0.5, 0.5), 0.25, 0.2));
}
