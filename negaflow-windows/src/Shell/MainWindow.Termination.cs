using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

public sealed partial class MainWindow
{
    private bool terminationInProgress;
    private bool terminationApproved;

    private async void OnAppWindowClosing(
        AppWindow sender,
        AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (terminationApproved || libraryHost is null)
        {
            return;
        }

        args.Cancel = true;
        if (terminationInProgress)
        {
            return;
        }

        terminationInProgress = true;
        LibraryDefectTerminationResult result;
        try
        {
            await ShellView.PrepareForTerminationAsync();
            string scansDirectory = new DiskStorageLocations(
                settingsStore.Current.Disk).Scans;
            result = await libraryHost.PrepareForTerminationAsync(scansDirectory);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or InvalidOperationException or COMException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            result = new LibraryDefectTerminationResult(
                LibraryDefectTerminationError.NativeBakeFailed,
                NativeFailureName: error.GetType().Name);
        }

        if (result.IsSuccess)
        {
            terminationApproved = true;
            terminationInProgress = false;
            Close();
            return;
        }

        try
        {
            await ShowTerminationFailureAsync(result);
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
        }
        finally
        {
            terminationInProgress = false;
        }
    }

    private async Task ShowTerminationFailureAsync(LibraryDefectTerminationResult result)
    {
        string messageKey = result.Error == LibraryDefectTerminationError.CatalogCommitFailed
            ? "developExportSaveFailed"
            : "libraryProcessApplyFailed";
        ContentDialog dialog = new()
        {
            XamlRoot = WindowRoot.XamlRoot,
            Title = AppResources.Get("developGrainMend", "Text"),
            Content = AppResources.Get(messageKey, "Text"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Close,
        };
        await dialog.ShowAsync();
    }
}
