namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 직접 그린 아이콘의 종류입니다. macOS SF Symbol 과 **뜻이 같은 자리**만 있습니다.
/// </summary>
public enum VectorIconKind
{
    /// <summary>macOS <c>folder.badge.gearshape</c>. 폴더 자리 고르기.</summary>
    FolderGear,

    /// <summary>macOS <c>crop</c>. 네 모서리 자르기 표식.</summary>
    Crop,

    /// <summary>macOS <c>rotate.right</c>. 시계 방향 90도.</summary>
    RotateRight,

    /// <summary>macOS <c>rotate.left</c>. 반시계 방향 90도.</summary>
    RotateLeft,

    /// <summary>macOS <c>arrow.left.and.right</c>. 좌우 반전.</summary>
    FlipHorizontal,

    /// <summary>macOS <c>arrow.up.and.down</c>. 상하 반전.</summary>
    FlipVertical,

    /// <summary>macOS <c>point.topleft.down.curvedto.point.bottomright.up</c>. 톤 커브.</summary>
    ToneCurve,

    /// <summary>macOS <c>circle.hexagongrid.fill</c>. 컬러 믹서.</summary>
    ColorMixer,

    /// <summary>macOS <c>camera.filters</c>. 겹친 원 셋 — 자동 색상·캘리브레이션·인화 출력.</summary>
    CameraFilters,

    /// <summary>macOS <c>chart.bar.xaxis</c>. 축 있는 막대 — 자동 레벨.</summary>
    LevelsChart,

    /// <summary>macOS <c>thermometer.medium</c>. 자동 화이트 밸런스.</summary>
    Thermometer,

    /// <summary>macOS <c>circle.righthalf.filled</c>. 흑백 토닝.</summary>
    HalfCircleRight,

    /// <summary>macOS <c>circle.lefthalf.striped.horizontal</c>. 로컬 조정.</summary>
    HalfCircleStriped,

    /// <summary>macOS <c>circle.dashed</c>. 원형 마스크.</summary>
    RadialMask,

    /// <summary>macOS <c>rectangle.split.3x1</c>. 선형 마스크.</summary>
    LinearMask,

    /// <summary>macOS <c>pentagon</c>. 다각형 마스크.</summary>
    PolygonMask,

    /// <summary>macOS <c>paintbrush</c>. 브러시 마스크.</summary>
    Paintbrush,

    /// <summary>macOS <c>scope</c>. 영역 결함 조준.</summary>
    Scope,

    /// <summary>macOS <c>bandage</c>. 결함 레이어.</summary>
    Bandage,

    /// <summary>macOS <c>rectangle.split.2x1</c>. 컬링 비교.</summary>
    CompareSplit,

    /// <summary>macOS <c>rectangle.grid.3x2</c>. 컬링 서베이.</summary>
    SurveyGrid,

    /// <summary>macOS <c>square.grid.2x2</c>. 컬링 격자.</summary>
    GridTwoByTwo,

    /// <summary>macOS <c>camera.macro</c>. 디테일·효과.</summary>
    CameraMacro,

    /// <summary>macOS <c>eye.slash</c>. 숨김.</summary>
    EyeSlash,

    /// <summary>macOS <c>eye</c>. 표시. 숨김과 짝이라 같은 눈 모양을 씁니다.</summary>
    Eye,

    /// <summary>macOS <c>rectangle.on.rectangle</c>. 복제 도장.</summary>
    CloneStamp,

    /// <summary>macOS <c>chevron.up.chevron.down</c>. 팝업 단추의 위·아래 겹화살.</summary>
    ChevronUpChevronDown,

    /// <summary>macOS <c>rectangle.inset.filled</c>. 인화 인스펙터의 레이아웃 탭.</summary>
    RectangleInsetFilled,

    /// <summary>macOS <c>photo.on.rectangle.angled</c>. 인화 인스펙터의 콘텐츠 탭.</summary>
    PhotoOnRectangle,
}

/// <summary>
/// 아이콘 획 자료입니다. 모두 <b>24×24 좌표계</b>에 그렸고 선으로만 이뤄집니다.
/// </summary>
/// <remarks>
/// <para>
/// **SF Symbols 를 베끼지 않았습니다.** Apple 글꼴은 라이선스상 쓸 수 없습니다
/// (<c>docs/audit/12-repos-and-licence.md</c>). 여기 있는 것은 같은 <b>뜻</b>을 나타내는
/// 그림을 직접 그린 것입니다 — 좌우 반전은 좌우 화살표, 다각형 마스크는 오각형처럼
/// 뜻이 통하면 됩니다. 선 모양까지 흉내 낼 이유는 없습니다.
/// </para>
/// <para>
/// **Segoe 에 뜻이 맞는 글리프가 있으면 그것을 씁니다.** 여기 있는 것은
/// <b>Segoe 에 없거나, 있는 것이 전혀 다른 뜻인</b> 자리뿐입니다. 근거는
/// <c>docs/audit/08a-icon-inventory.md</c> 에 자리별로 적혀 있습니다.
/// </para>
/// <para>
/// 24×24 를 벗어나게 그리지 마십시오. <see cref="VectorIcon"/> 이 그 상자를
/// 기준으로 크기를 맞춥니다.
/// </para>
/// </remarks>
internal static class VectorIconPaths
{
    internal static string Data(VectorIconKind kind) => kind switch
    {
        // macOS `crop`: 네모 본체에 좌상단·우하단 돌출선을 함께 둡니다.
        VectorIconKind.Crop =>
            "M 8,3 L 8,7 L 4,7 " +
            "M 8,7 L 17,7 L 17,17 L 8,17 L 8,7 " +
            "M 17,17 L 21,17 M 17,17 L 17,21",

        // 원호 + 화살촉. macOS `rotate.right`의 화살촉과 원호 방향.
        VectorIconKind.RotateRight =>
            "M 12,4 A 8,8 0 1 0 19.6,9.6 M 12,4 L 15.6,6.4 M 12,4 L 9.4,7.2",

        // 위의 좌우 대칭. macOS `rotate.left`의 화살촉과 원호 방향.
        VectorIconKind.RotateLeft =>
            "M 12,4 A 8,8 0 1 1 4.4,9.6 M 12,4 L 8.4,6.4 M 12,4 L 14.6,7.2",

        // 세로 축과 좌우 화살표 둘.
        VectorIconKind.FlipHorizontal =>
            "M 12,3 L 12,21 M 3,12 L 9,12 M 6,9 L 3,12 L 6,15 M 21,12 L 15,12 M 18,9 L 21,12 L 18,15",

        // 가로 축과 상하 화살표 둘.
        VectorIconKind.FlipVertical =>
            "M 3,12 L 21,12 M 12,3 L 12,9 M 9,6 L 12,3 L 15,6 M 12,21 L 12,15 M 9,18 L 12,21 L 15,18",

        // 상자 안의 S 곡선. 왼쪽 아래에서 오른쪽 위로 오른다.
        VectorIconKind.ToneCurve =>
            "M 4,20 L 4,4 M 4,20 L 20,20 M 4,20 C 9,20 8,7 20,4",

        // 원 일곱 개를 육각으로 — 가운데 하나, 둘레 여섯.
        VectorIconKind.ColorMixer =>
            "M 12,12 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 12,6 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 12,18 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 6.8,9 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 17.2,9 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 6.8,15 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0 " +
            "M 17.2,15 m -2.6,0 a 2.6,2.6 0 1 0 5.2,0 a 2.6,2.6 0 1 0 -5.2,0",

        // 겹친 원 셋 — 컬러 필터.
        VectorIconKind.CameraFilters =>
            "M 12,8.5 m -4.5,0 a 4.5,4.5 0 1 0 9,0 a 4.5,4.5 0 1 0 -9,0 " +
            "M 8,15.5 m -4.5,0 a 4.5,4.5 0 1 0 9,0 a 4.5,4.5 0 1 0 -9,0 " +
            "M 16,15.5 m -4.5,0 a 4.5,4.5 0 1 0 9,0 a 4.5,4.5 0 1 0 -9,0",

        // 바닥 축과 높이가 다른 막대 넷.
        VectorIconKind.LevelsChart =>
            "M 3,20 L 21,20 M 6,20 L 6,13 M 10,20 L 10,7 M 14,20 L 14,10 M 18,20 L 18,4",

        // 눈금 있는 관과 아래쪽 구.
        VectorIconKind.Thermometer =>
            "M 12,15.5 L 12,5 A 2,2 0 0 1 16,5 L 16,15.5 " +
            "A 4.5,4.5 0 1 1 12,15.5 M 16,8 L 18.5,8 M 16,11 L 18.5,11",

        // 원과 오른쪽 반 채움.
        VectorIconKind.HalfCircleRight =>
            "M 12,3 A 9,9 0 1 1 12,21 A 9,9 0 1 1 12,3 M 12,3 L 12,21 " +
            "M 12,6 L 14.6,6 M 12,9 L 17.6,9 M 12,12 L 18.4,12 M 12,15 L 17.6,15 M 12,18 L 14.6,18",

        // 원과 왼쪽 반 가로 줄무늬.
        VectorIconKind.HalfCircleStriped =>
            "M 12,3 A 9,9 0 1 1 12,21 A 9,9 0 1 1 12,3 M 12,3 L 12,21 " +
            "M 12,6 L 9.4,6 M 12,9 L 6.4,9 M 12,12 L 5.6,12 M 12,15 L 6.4,15 M 12,18 L 9.4,18",

        // 점선 원 — 여덟 토막.
        VectorIconKind.RadialMask =>
            "M 12,3.5 A 8.5,8.5 0 0 1 18,6 M 20.5,12 A 8.5,8.5 0 0 0 18,6 " +
            "M 20.5,12 A 8.5,8.5 0 0 1 18,18 M 12,20.5 A 8.5,8.5 0 0 0 18,18 " +
            "M 12,20.5 A 8.5,8.5 0 0 1 6,18 M 3.5,12 A 8.5,8.5 0 0 0 6,18 " +
            "M 3.5,12 A 8.5,8.5 0 0 1 6,6 M 12,3.5 A 8.5,8.5 0 0 0 6,6",

        // 가로로 셋 나뉜 상자.
        VectorIconKind.LinearMask =>
            "M 3,6 L 21,6 L 21,18 L 3,18 Z M 9,6 L 9,18 M 15,6 L 15,18",

        // 오각형.
        VectorIconKind.PolygonMask =>
            "M 12,3.5 L 20.5,9.7 L 17.2,19.7 L 6.8,19.7 L 3.5,9.7 Z",

        // 붓 — 손잡이와 털.
        VectorIconKind.Paintbrush =>
            "M 20.5,3.5 L 10.5,13.5 M 20.5,3.5 L 17.5,3.5 L 7.5,13.5 " +
            "M 20.5,3.5 L 20.5,6.5 L 10.5,16.5 M 7.5,13.5 L 10.5,16.5 " +
            "M 7.5,13.5 C 5,14 3.5,16.5 3.5,20.5 C 7.5,20.5 10,19 10.5,16.5",

        // 조준 — 원과 열십자.
        VectorIconKind.Scope =>
            "M 12,5 A 7,7 0 1 1 12,19 A 7,7 0 1 1 12,5 " +
            "M 12,2.5 L 12,8 M 12,16 L 12,21.5 M 2.5,12 L 8,12 M 16,12 L 21.5,12",

        // 반창고 — 기운 띠와 가운데 판.
        VectorIconKind.Bandage =>
            "M 7.5,3.5 L 20.5,16.5 A 4.6,4.6 0 0 1 16.5,20.5 L 3.5,7.5 " +
            "A 4.6,4.6 0 0 1 7.5,3.5 Z M 8.5,15.5 L 15.5,8.5 " +
            "M 10.5,11 L 11.5,12 M 12.5,13 L 13.5,14",

        // 좌우로 둘 나뉜 상자.
        VectorIconKind.CompareSplit =>
            "M 3,6 L 21,6 L 21,18 L 3,18 Z M 12,6 L 12,18",

        // 3열 2행 격자.
        VectorIconKind.SurveyGrid =>
            "M 3,6 L 21,6 L 21,18 L 3,18 Z M 9,6 L 9,18 M 15,6 L 15,18 M 3,12 L 21,12",

        // 2×2 격자.
        VectorIconKind.GridTwoByTwo =>
            "M 4,4 L 20,4 L 20,20 L 4,20 Z M 12,4 L 12,20 M 4,12 L 20,12",

        // 매크로 — 꽃잎 넷과 가운데 원.
        VectorIconKind.CameraMacro =>
            "M 12,12 m -2.5,0 a 2.5,2.5 0 1 0 5,0 a 2.5,2.5 0 1 0 -5,0 " +
            "M 12,9.5 C 12,5 9,3 6.5,4.5 C 4,6 5,9.5 9.5,10.5 " +
            "M 14.5,12 C 19,12 21,9 19.5,6.5 C 18,4 14.5,5 13.5,9.5 " +
            "M 12,14.5 C 12,19 15,21 17.5,19.5 C 20,18 19,14.5 14.5,13.5 " +
            "M 9.5,12 C 5,12 3,15 4.5,17.5 C 6,20 9.5,19 10.5,14.5",

        // 눈과 가로지르는 빗금.
        VectorIconKind.EyeSlash =>
            "M 3,12 C 6,7.5 9,5.5 12,5.5 C 15,5.5 18,7.5 21,12 " +
            "C 18,16.5 15,18.5 12,18.5 C 9,18.5 6,16.5 3,12 Z " +
            "M 12,9 A 3,3 0 1 1 12,15 A 3,3 0 1 1 12,9 M 4,20 L 20,4",

        // 겹친 사각형 둘 — 복제 도장.
        VectorIconKind.CloneStamp =>
            "M 3.5,8.5 L 15.5,8.5 L 15.5,20.5 L 3.5,20.5 Z " +
            "M 8.5,8.5 L 8.5,3.5 L 20.5,3.5 L 20.5,15.5 L 15.5,15.5",

        // macOS chevron.up.chevron.down — Form 안 Picker 가 값 오른쪽에 다는 표식입니다.
        // Segoe 의 E70D/E70E 는 화살이 하나뿐이라 뜻이 다릅니다.
        VectorIconKind.ChevronUpChevronDown =>
            "M 7.5,10.5 L 12,6 L 16.5,10.5 " +
            "M 7.5,13.5 L 12,18 L 16.5,13.5",

        // macOS rectangle.inset.filled — 판 안에 앉힌 사진 한 장. 바깥 테두리 안에
        // 채운 사각형을 겹칩니다(선으로만 그리므로 안쪽 사각형이 그 자리입니다).
        VectorIconKind.RectangleInsetFilled =>
            "M 3,6 L 21,6 L 21,18 L 3,18 Z " +
            "M 6.5,9.5 L 17.5,9.5 L 17.5,14.5 L 6.5,14.5 Z",

        // macOS photo.on.rectangle.angled — 뒤에 한 장 더 겹친 사진.
        VectorIconKind.PhotoOnRectangle =>
            "M 8,4.5 L 20.5,4.5 L 20.5,15 " +
            "M 3.5,8.5 L 16.5,8.5 L 16.5,20 L 3.5,20 Z " +
            "M 3.5,17 L 7.5,13 L 10.5,16 L 12.5,14 L 16.5,18",

        // 빗금 없는 같은 눈 — 켜짐과 꺼짐이 한 쌍으로 보이도록 모양을 맞춥니다.
        // macOS folder.badge.gearshape — 폴더를 **고르는** 자리. 폴더 윤곽 오른쪽 아래에
        // 톱니를 답니다. Segoe 에는 폴더+톱니가 없어 직접 그립니다.
        VectorIconKind.FolderGear =>
            "M 3,7 A 1.6,1.6 0 0 1 4.6,5.4 L 9.2,5.4 L 11,7.6 L 19.4,7.6 " +
            "A 1.6,1.6 0 0 1 21,9.2 L 21,13.4 M 3,7 L 3,17.4 " +
            "A 1.6,1.6 0 0 0 4.6,19 L 12.4,19 " +
            "M 17.4,15 A 2,2 0 1 1 17.4,19.01 A 2,2 0 1 1 17.4,15 " +
            "M 17.4,13.2 L 17.4,14.4 M 17.4,19.6 L 17.4,20.8 " +
            "M 20.2,15.4 L 19.2,16 M 15.6,18 L 14.6,18.6 " +
            "M 20.2,18.6 L 19.2,18 M 15.6,16 L 14.6,15.4",

        VectorIconKind.Eye =>
            "M 3,12 C 6,7.5 9,5.5 12,5.5 C 15,5.5 18,7.5 21,12 " +
            "C 18,16.5 15,18.5 12,18.5 C 9,18.5 6,16.5 3,12 Z " +
            "M 12,9 A 3,3 0 1 1 12,15 A 3,3 0 1 1 12,9",

        _ => string.Empty,
    };
}
