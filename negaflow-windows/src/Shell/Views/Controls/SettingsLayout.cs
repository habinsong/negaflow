namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 설정창 배치 수치입니다. macOS <c>Form(.grouped)</c> 화면을 **화소 단위로 재서** 넣었습니다.
/// </summary>
/// <remarks>
/// <para>
/// 출처: <c>C:\Users\habin\Downloads\맥negaflow 스크린샷\설정\*.png</c>. 스크린샷은 1x 논리
/// 화소이며(창 폭 758px ≈ 760pt), 아래 값은 그 그림에서 직접 잰 것입니다. 눈대중이 아닙니다.
/// </para>
/// <para>
/// **여기 없는 수치를 자리마다 새로 지어내지 마십시오.** 그렇게 해서 지금 설정창이
/// 탭마다 크기가 다르고 컨트롤이 왼쪽으로 쏠려 있습니다. 새 수치가 필요하면 스크린샷에서
/// 재서 여기에 넣고, 어디서 쟀는지 적으십시오.
/// </para>
/// </remarks>
internal static class SettingsLayout
{
    /// <summary>macOS <c>.frame(width: 760, height: 640)</c>.</summary>
    internal const double WindowWidth = 760;

    internal const double WindowHeight = 640;

    /// <summary>탭 한 칸의 간격입니다. 일반.png 의 여덟 아이콘 중심 236…637 → 400.7/7 = 57.2.</summary>
    internal const double TabCellWidth = 57;

    /// <summary>선택 배경의 크기입니다. 일반.png 에서 x 209..263(54) · y 69..117(48).</summary>
    internal const double TabCellHeight = 48;

    /// <summary>선택 배경 폭입니다. 칸 간격 57 보다 3 좁아 칸 사이가 붙어 보이지 않습니다.</summary>
    internal const double TabCellHighlightWidth = 54;

    /// <summary>선택 칸 배경의 라운딩입니다. 3배 확대에서 30 → 10.</summary>
    internal const double TabCellCornerRadius = 10;

    /// <summary>탭바 전체 높이(구분선 제외)입니다. 제목 표시줄 아래 62 → 구분선 125.</summary>
    internal const double TabBarHeight = 62;

    /// <summary>내용 좌우 여백입니다. 창 안쪽 758 에서 카드가 84..788 이므로 27.</summary>
    internal const double ContentHorizontalMargin = 27;

    /// <summary>내용 위 여백입니다. 구분선 아래 첫 섹션 머리까지 20.</summary>
    internal const double ContentTopMargin = 20;

    internal const double ContentBottomMargin = 28;

    /// <summary>섹션과 섹션 사이입니다. 앞 카드 아래 291 → 다음 머리글 상자 321.</summary>
    internal const double SectionSpacing = 30;

    /// <summary>섹션 머리와 카드 사이입니다. 머리글 상자 아래 337 → 카드 위 347.</summary>
    internal const double SectionHeaderGap = 10;

    internal const double SectionHeaderFontSize = 13;

    /// <summary>카드 라운딩입니다.</summary>
    internal const double CardCornerRadius = 10;

    /// <summary>컨트롤이 있는 행의 높이입니다. 172→213→254 로 41 간격.</summary>
    internal const double RowHeight = 41;

    /// <summary>
    /// 컨트롤이 없는 행(값 글자·스위치)의 높이입니다. macOS Form 은 행을 내용에 맞춰
    /// 재므로 팝업 단추가 없는 줄은 더 낮습니다 — 개발자 모드 255..291, 결함 제거 원본
    /// 388..424 로 37.
    /// </summary>
    internal const double CompactRowHeight = 37;

    /// <summary>
    /// 경로 한 줄의 높이입니다. 디스크_윗부분.png 에서 분리선이 216·256·296… 으로 40 간격.
    /// </summary>
    internal const double PathRowHeight = 40;

    /// <summary>캡슐만 있는 줄의 높이입니다. 같은 그림에서 카드 위 172 → 첫 분리선 216.</summary>
    internal const double CapsuleRowHeight = 44;

    /// <summary>행 좌우 안쪽 여백입니다. 카드 84..787, 라벨 첫 글자 94, 컨트롤 오른쪽 끝 777.</summary>
    internal const double RowHorizontalPadding = 10;

    /// <summary>분리선 좌우 들여쓰기입니다. 카드 84..787, 선 94..777.</summary>
    internal const double SeparatorInset = 10;

    /// <summary>본문 글자 크기입니다.</summary>
    internal const double RowFontSize = 13;

    /// <summary>본문 줄 간격입니다. 법적고지.png 의 글자 위쪽이 185 · 201 · 217 로 16 간격.</summary>
    internal const double BodyLineHeight = 16;

    /// <summary>카드 아래 붙는 설명문 글자 크기입니다. 글자 높이 8 → 11.</summary>
    internal const double FootnoteFontSize = 11;

    /// <summary>설명문 줄 간격입니다. 세 줄의 글자 위쪽이 474 · 487 · 500 으로 13 간격.</summary>
    internal const double FootnoteLineHeight = 13;

    /// <summary>설명문 위아래 여백입니다. 분리선 462 → 첫 줄 상자 471, 마지막 줄 510 → 521.</summary>
    internal const double FootnoteVerticalPadding = 10;
}
