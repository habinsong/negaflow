using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>
/// macOS 출력 소스 패널입니다. 형식·폴더·파일명·레시피를 고르고 미리보기를 갱신합니다.
/// 실제 파일 쓰기는 <see cref="DevelopExportRunner"/> 가 맡습니다.
/// </summary>
public sealed partial class DevelopExportPanel : UserControl
{
    internal ExportSettings exportSettings = new();
    internal QuickExportSettings quickExportSettings = new();
    internal ExportRecipeLibrary exportRecipes = new();
    internal bool isSynchronizingExport;
    internal WorkspacePresentationState? workspaceState;
    internal DevelopPanelState? panel;
    internal LibraryHostService? libraryHost;
    internal Microsoft.UI.WindowId? importWindowId;
    internal string engineVersion = "unknown";
    internal readonly DevelopExportControlSync sync;
    internal readonly DevelopExportCopy copy;
    internal readonly DevelopExportRecipes recipes;
    internal readonly DevelopExportRunner runner;

    public DevelopExportPanel()
    {
        InitializeComponent();
        // 세 슬라이더의 값 글자는 `85%` 인데 썸 툴팁은 붙이지 않으면 `85.0000` 으로 나옵니다.
        // 같은 칸을 두 가지로 읽지 않도록 값 글자와 같은 규칙을 답니다. XAML 로 거는
        // `ThumbToolTipValueConverter` 는 걸리지 않으므로 여기서 붙입니다.
        foreach (Slider slider in new[]
        {
            ExportJpegQualitySlider,
            ExportSharpeningSlider,
            QuickExportJpegQualitySlider,
        })
        {
            slider.ThumbToolTipValueConverter =
                new Negaflow.Shell.Views.Controls.PercentSuffixThumbConverter();
        }
        sync = new DevelopExportControlSync(this);
        copy = new DevelopExportCopy(this);
        recipes = new DevelopExportRecipes(this);
        runner = new DevelopExportRunner(this);
    }

    public ExportSettings Settings => exportSettings;

    public QuickExportSettings QuickSettings => quickExportSettings;

    public ExportRecipeLibrary Recipes => exportRecipes;

    public void Attach(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
    }

    public void Bind(
        DevelopPanelState hostPanel,
        LibraryHostService host,
        Microsoft.UI.WindowId windowId,
        string version)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        ArgumentNullException.ThrowIfNull(host);
        panel = hostPanel;
        libraryHost = host;
        importWindowId = windowId;
        engineVersion = version;
    }

    public void ApplyPreferences(
        ExportSettings export,
        QuickExportSettings quick,
        ExportRecipeLibrary library)
    {
        exportSettings = export;
        quickExportSettings = quick;
        exportRecipes = library;
        sync.SynchronizeExportControls();
    }

    public void Localize() => copy.LocalizeOutputPanel();

    public void RefreshPreview() => sync.UpdateExportPreview();

    /// <summary>
    /// 화면이 따로 꽂아 주는 빠른 내보내기입니다. macOS <c>ExportSection(onQuickExport:)</c>
    /// 자리이며, 꽂지 않으면 패널이 자기 기본 동작을 합니다.
    /// </summary>
    public Func<Task>? RunQuickExport { get; set; }

    /// <summary>
    /// 화면이 따로 꽂아 주는 내보내기입니다. macOS <c>ExportSection(onExport:)</c> 자리이며,
    /// 인화뷰가 판 합성본을 쓰기 위해 씁니다.
    /// </summary>
    public Func<Task>? RunExport { get; set; }

    /// <summary>
    /// 지금 몇 장 중 몇 장까지 갔는지입니다. 두 알약에 그대로 얹고, 셸이 위 막대에도
    /// 같은 값을 보여 줍니다.
    /// </summary>
    public ExportProgress Progress
    {
        get;
        private set
        {
            field = value;
            ExportButton.Progress = value;
            QuickExportButton.Progress = value;
            ProgressChanged?.Invoke(this, value);
        }
    }

    /// <summary>진행이 바뀌었습니다. 위 막대가 이 값을 씁니다.</summary>
    public event EventHandler<ExportProgress>? ProgressChanged;

    /// <summary>내보내기가 시작·진행·끝났음을 알립니다. 러너만 부릅니다.</summary>
    internal void ReportProgress(ExportProgress progress) => Progress = progress;

    /// <summary>
    /// 인화뷰처럼 <b>종이 판</b>에 얹어 내보내는 화면인지입니다. macOS
    /// <c>ExportSection(usesPaperLayout:)</c> 와 같으며, 참이면 빠른 내보내기의 "크기(긴 변)"
    /// 줄이 사라집니다 - 판 크기와 해상도가 이미 픽셀 수를 정하기 때문입니다.
    /// </summary>
    public bool UsesPaperLayout
    {
        get;
        set
        {
            field = value;
            SetQuickExportRowVisible(QuickExportSizeRow, !value);
        }
    }

    /// <summary>
    /// 한 판에 <b>여러 장을 얹는</b> 배치인지입니다. macOS
    /// <c>ExportSection(usesCompositeLayout:)</c> — <c>layoutMode != .singleImage</c> 입니다.
    /// 참이면 내보내기 단추는 한 장이어도 숫자를 답니다: 그 숫자가 사진 수가 아니라
    /// <b>나올 파일 수</b>이기 때문입니다.
    /// </summary>
    public bool UsesCompositeLayout { get; set; }

    /// <summary>
    /// 지금 설정으로 나올 <b>판 수</b>입니다. macOS <c>printExportOutputCount</c> 자리이며,
    /// 인화뷰가 레이아웃과 고른 장수에서 계산해 꽂습니다.
    /// </summary>
    public Func<int>? PaperOutputCount { get; set; }

    /// <summary>
    /// 빠른 내보내기 카드의 줄 하나를 켜고 끕니다. 줄이 늘거나 줄면 <b>분리선을 다시</b>
    /// 놓습니다 — 그러지 않으면 접힌 줄 앞의 선만 빈 자리에 남습니다.
    /// </summary>
    internal void SetQuickExportRowVisible(FrameworkElement row, bool visible)
    {
        ArgumentNullException.ThrowIfNull(row);
        Visibility wanted = Visible(visible);
        if (row.Visibility == wanted)
        {
            return;
        }
        row.Visibility = wanted;
        QuickExportCard.Apply();
    }

    internal void SynchronizeExportControls() => sync.SynchronizeExportControls();

    internal static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>지금 열려 있는 세부 탭입니다 — macOS <c>selectedDetailPage</c>.</summary>
    internal string SelectedDetailPage => ExportQualityTabButton.IsChecked == true
        ? "quality"
        : ExportSourceTabButton.IsChecked == true ? "source" : "file";

    /// <summary>
    /// 내보내기 결과입니다. **단추 아래에 글로 띄우지 않습니다.**
    /// </summary>
    /// <remarks>
    /// 저장한 경로·진행·실패를 단추 바로 밑에 쌓으면 카드가 움직이고, 성공했을 때조차
    /// 읽을 일이 없는 줄이 남습니다. 진행은 도구줄의 원형 표시가, 결과는 파일 자체가
    /// 말합니다. 다만 조용히 삼키지는 않습니다 — 진단 기록에는 남깁니다.
    /// </remarks>
    internal void SetOutputStatus(string text)
    {
        if (text.Length != 0)
        {
            PreviewTrace.Write("export status " + text);
        }
    }

    /// <summary>
    /// 출력 패널의 값을 하나 바꿔 저장하고, 저장된 값을 다시 컨트롤에 되비춥니다. 설정이
    /// 앱 설정 파일에 살기 때문에 여기가 유일한 쓰기 지점입니다.
    /// </summary>
    internal void MutateExportSettings(Func<ExportSettings, ExportSettings> update)
    {
        if (isSynchronizingExport)
        {
            return;
        }
        exportSettings = update(exportSettings).Normalize();
        workspaceState?.UpdateExport(_ => exportSettings);
        SynchronizeExportControls();
    }

    private void MutateQuickExportSettings(Func<QuickExportSettings, QuickExportSettings> update)
    {
        if (isSynchronizingExport)
        {
            return;
        }
        quickExportSettings = update(quickExportSettings).Normalize();
        workspaceState?.UpdateQuickExport(_ => quickExportSettings);
        SynchronizeExportControls();
    }

    /// <summary>
    /// 담아 둔 내보내기 설정을 고릅니다. 목적지와 파일명 패턴은 지금 것을 지킵니다 — 프리셋을
    /// 고르는 것이 내보낼 폴더를 바꾸는 뜻은 아닙니다.
    /// </summary>
    private void OnExportRecipeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingExport)
        {
            return;
        }
        string? recipeId = ExportRecipeSelector.SelectedTag as string;
        workspaceState?.UpdateExportRecipes(library => library with { SelectedId = recipeId });
        exportRecipes = exportRecipes with { SelectedId = recipeId };
        if (exportRecipes.Selected is { } recipe)
        {
            MutateExportSettings(recipe.ApplyTo);
        }
        else
        {
            SynchronizeExportControls();
        }
    }

    internal void BuildExportRecipeMenu() => recipes.BuildExportRecipeMenu();

    internal async void RenameExportRecipe(ExportRecipe recipe) =>
        await recipes.RenameExportRecipe(recipe);

    internal void SaveCurrentExportRecipe() => recipes.SaveCurrentExportRecipe();

    internal void UpdateExportRecipes(Func<ExportRecipeLibrary, ExportRecipeLibrary> update) =>
        recipes.UpdateExportRecipes(update);

    /// <summary>
    /// 세부 탭이 바뀌면 그 탭에 속한 행만 남깁니다. macOS 는 <c>switch selectedDetailPage</c>
    /// 로 행 자체를 갈아 끼우므로, 여기서도 <b>행을 숨겨</b> 분리선까지 따라가게 합니다 —
    /// 페이지를 통째로 접으면 카드 안 분리선이 옛 자리에 남습니다.
    /// </summary>
    internal void OnExportDetailTabChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        // XAML 의 `IsChecked="True"` 는 **InitializeComponent 안에서** 이 이벤트를 냅니다.
        // 그때는 아직 뒤쪽 컨트롤도, 아래 도우미들도 없습니다 - 여기서 되비추려 들면
        // 창이 만들어지다 말고 죽습니다(실측: XamlParseException "Failed to assign to
        // property ToggleButton.IsChecked").
        if (sync is null || ExportFormatSelector is null)
        {
            return;
        }
        SynchronizeExportControls();
    }

    private async void OnExportFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (await PickExportFolderAsync() is { } folder)
        {
            MutateExportSettings(value => value with { FolderPath = folder });
        }
    }

    private async void OnQuickExportFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (await PickExportFolderAsync() is { } folder)
        {
            MutateQuickExportSettings(value => value with { FolderPath = folder });
        }
    }

    private async Task<string?> PickExportFolderAsync()
    {
        if (importWindowId is not { } windowId)
        {
            return null;
        }
        var picker = new Microsoft.Windows.Storage.Pickers.FolderPicker(windowId)
        {
            CommitButtonText = AppResources.Get("developExportFolderChange", "Content"),
        };
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            return picked?.Path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            SetOutputStatus(AppResources.Get("developExportFolderFailed", "Text"));
            return null;
        }
    }

    private void UpdateExportPreview() => sync.UpdateExportPreview();

    /// <summary>macOS `reveal` — 산출물이 놓인 폴더를 탐색기로 엽니다.</summary>
    private void OnExportRevealClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RevealFolder(exportSettings.FolderPath);
    }

    private void OnQuickExportRevealClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RevealFolder(quickExportSettings.FolderPath);
    }

    /// <summary>
    /// 폴더가 아직 없으면 만들고 엽니다. macOS `revealExportFolder` 도 같은 순서입니다 —
    /// 한 번도 내보내지 않았어도 어디로 나갈지 볼 수 있어야 합니다.
    /// </summary>
    private void RevealFolder(string folderPath)
    {
        if (string.IsNullOrWhiteSpace(folderPath))
        {
            return;
        }
        try
        {
            _ = Directory.CreateDirectory(folderPath);
            using System.Diagnostics.Process? opened = System.Diagnostics.Process.Start(
                new System.Diagnostics.ProcessStartInfo(folderPath) { UseShellExecute = true });
            _ = opened;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or
            System.ComponentModel.Win32Exception)
        {
            SetOutputStatus(AppResources.Get("developExportFolderFailed", "Text"));
        }
    }

    private async void OnExportClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        // macOS `onExport ?? model.exportSelectionToFolder` 와 같습니다.
        await (RunExport is { } run ? run() : runner.RunExportAsync());
    }

    private async void OnQuickExportClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        // macOS `onQuickExport ?? model.quickExportSelection` — 화면이 따로 꽂아 준 것이
        // 없으면 패널이 자기 기본 동작을 합니다. 이것이 없어서 인화뷰의 빠른 내보내기가
        // 눌러도 아무 일이 없었습니다.
        await (RunQuickExport is { } run ? run() : runner.RunQuickExportAsync());
    }
}
