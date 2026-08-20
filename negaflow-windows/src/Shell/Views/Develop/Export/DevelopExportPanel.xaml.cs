using System.Globalization;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

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

    public Func<Task>? RunQuickExport { get; set; }

    internal void SynchronizeExportControls() => sync.SynchronizeExportControls();

    internal static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

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
    private void OnExportRecipeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingExport ||
            ExportRecipeSelector.SelectedItem is not ComboBoxItem item)
        {
            return;
        }
        string? recipeId = item.Tag as string;
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

    internal void OnExportDetailTabChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportFilePage is null)
        {
            return;
        }
        ExportFilePage.Visibility = Visible(ExportFileTabButton.IsChecked == true);
        ExportQualityPage.Visibility = Visible(ExportQualityTabButton.IsChecked == true);
        ExportSourcePage.Visibility = Visible(ExportSourceTabButton.IsChecked == true);
    }

    private void OnExportFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportFormatSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopExportFormat format))
        {
            return;
        }
        MutateExportSettings(value => value with { Format = format });
    }

    private void OnExportNamePatternChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        // 사용자가 타이핑하는 중에는 패턴이 잠깐 잘못될 수 있습니다. 잘못된 패턴을 정규화가
        // 기본값으로 되돌려 버리면 글자를 지울 수 없으므로 원문 그대로 담고 미리보기로만 알립니다.
        if (isSynchronizingExport)
        {
            return;
        }
        exportSettings = exportSettings with
        {
            NamingTemplate = ExportNamingTemplate.Normalize(ExportNamePatternBox.Text),
        };
        workspaceState?.UpdateExport(_ => exportSettings);
        UpdateExportPreview();
    }

    private void OnExportSequenceStartChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        if (double.IsNaN(args.NewValue))
        {
            return;
        }
        MutateExportSettings(value => value with { SequenceStart = (int)args.NewValue });
    }

    private void OnExportTiffCompressionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportTiffCompressionSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopTiffCompression compression))
        {
            return;
        }
        MutateExportSettings(value => value with { TiffCompression = compression });
    }

    /// <summary>
    /// 채널당 비트입니다. macOS 처럼 형식마다 따로 기억합니다 — 보관용 TIFF 는 16, 화면용 PNG 는
    /// 8 로 두는 사람이 형식을 오갈 때마다 다시 고르지 않아야 합니다.
    /// </summary>
    private void OnExportBitDepthChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportBitDepthSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !int.TryParse(tag, out int depth))
        {
            return;
        }
        MutateExportSettings(value => value.Format == DevelopExportFormat.Tiff16
            ? value with { TiffBitDepth = depth }
            : value with { PngBitDepth = depth });
    }

    private void OnExportPreserveAlphaToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isSynchronizingExport)
        {
            MutateExportSettings(value => value with
            {
                PreserveAlpha = ExportPreserveAlphaToggle.IsOn,
            });
        }
    }

    private void OnExportDpiChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportDpiSelector.SelectedItem is not ComboBoxItem { Tag: int dpi })
        {
            return;
        }
        MutateExportSettings(value => value with { Dpi = dpi });
    }

    private void OnExportSizeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportSizeSelector.SelectedItem is not ComboBoxItem { Tag: int longEdge })
        {
            return;
        }
        MutateExportSettings(value => value with { LongEdge = longEdge });
    }

    private void OnExportJpegQualityChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        MutateExportSettings(value => value with { JpegQuality = args.NewValue / 100.0 });
    }

    private void OnExportSharpeningChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        MutateExportSettings(value => value with { OutputSharpening = args.NewValue / 100.0 });
    }

    private void OnExportSharpeningMediumChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportSharpeningMediumSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out OutputSharpeningMedium medium))
        {
            return;
        }
        MutateExportSettings(value => value with { OutputSharpeningMedium = medium });
    }

    private void OnExportMainFlatMasterToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with
        {
            WriteMainFlatMaster = ExportMainFlatMasterToggle.IsOn,
        });
    }

    private void OnExportOriginalRawToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with
        {
            WriteOriginalRaw = ExportOriginalRawToggle.IsOn,
        });
    }

    private void OnExportSidecarToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with { WriteSidecar = ExportSidecarToggle.IsOn });
    }

    /// <summary>
    /// 게시하는 파일에 무엇을 적을지입니다. 기본은 최소 — 원본이 담고 있던 위치나 장비 정보를
    /// 사용자가 고르지 않았는데 흘려보내지 않습니다.
    /// </summary>
    private void OnExportMetadataPolicyChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingExport)
        {
            return;
        }
        ExportMetadataPolicy policy = ExportMetadataSelector.SelectedIndex switch
        {
            1 => ExportMetadataPolicy.CopyrightOnly,
            2 => ExportMetadataPolicy.RemoveLocation,
            3 => ExportMetadataPolicy.All,
            _ => ExportMetadataPolicy.Minimal,
        };
        MutateExportSettings(value => value with { MetadataPolicy = policy });
    }

    private void OnQuickExportFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportFormatSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopExportFormat format))
        {
            return;
        }
        MutateQuickExportSettings(value => value with { Format = format });
    }

    private void OnQuickExportDpiChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportDpiSelector.SelectedItem is not ComboBoxItem { Tag: int dpi })
        {
            return;
        }
        MutateQuickExportSettings(value => value with { Dpi = dpi });
    }

    private void OnQuickExportSizeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportSizeSelector.SelectedItem is not ComboBoxItem { Tag: int longEdge })
        {
            return;
        }
        MutateQuickExportSettings(value => value with { LongEdge = longEdge });
    }

    private void OnQuickExportJpegQualityChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        MutateQuickExportSettings(value => value with { JpegQuality = args.NewValue / 100.0 });
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
            OutputStatusText.Text = AppResources.Get("developExportFolderFailed", "Text");
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
            OutputStatusText.Text = AppResources.Get("developExportFolderFailed", "Text");
        }
    }

    private async void OnExportClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await runner.RunExportAsync();
    }

    private async void OnQuickExportClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        // macOS `onQuickExport ?? model.quickExportSelection` — 화면이 따로 꽂아 준 것이
        // 없으면 패널이 자기 기본 동작을 합니다. 이것이 없어서 인화뷰의 빠른 내보내기가
        // 눌러도 아무 일이 없었습니다.
        QuickExportButton.IsEnabled = false;
        try
        {
            await (RunQuickExport is { } run ? run() : runner.RunQuickExportAsync());
        }
        finally
        {
            UpdateExportPreview();
        }
    }
}
