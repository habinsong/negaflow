using System.IO;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Info;

/// <summary>
/// macOS 정보 카드의 여섯 줄입니다. 원본과 Sidecar 는 지금 알 수 있는 사실이고, 카메라·날짜·
/// 제목·키워드는 아직 EXIF/IPTC 를 읽지 않으므로 macOS 의 빈 상태와 같은 "— · —" 입니다.
/// 읽지 않은 값을 추측해서 채우지 않습니다.
/// </summary>
public sealed partial class DevelopInfoCard : UserControl
{
    public DevelopInfoCard() => InitializeComponent();

    public void Update(LibraryFrameSnapshot? frame)
    {
        if (Rows is null)
        {
            return;
        }
        string cardTitle = AppResources.Get("developInfoCard", "Text");
        TitleText.Text = cardTitle;
        // 이름이 없는 Border 는 접근성 트리에 나오지 않습니다 — 화면 낭독기도, 검증도 못 봅니다.
        AutomationProperties.SetName(Card, cardTitle);
        Rows.ItemsSource = DevelopInfoCardProjection.Rows(
            frame,
            CardText(),
            File.Exists);
    }

    private static DevelopInfoCardText CardText() => new(
        AppResources.Get("developInfoSource", "Text"),
        AppResources.Get("developInfoSidecar", "Text"),
        AppResources.Get("developInfoCamera", "Text"),
        AppResources.Get("developInfoDate", "Text"),
        AppResources.Get("developInfoTitle", "Text"),
        AppResources.Get("developInfoKeywords", "Text"),
        AppResources.Get("developInfoNotAvailable", "Text"),
        AppResources.Get("developInfoOriginScan", "Text"),
        AppResources.Get("developInfoOriginImport", "Text"),
        AppResources.Get("developInfoUnknown", "Text"),
        AppResources.Get("developInfoSidecarNotFound", "Text"));
}
