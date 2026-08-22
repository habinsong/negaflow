using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>
/// 출력 패널에서 <b>값 하나를 고르거나 끌었을 때</b>의 자리입니다. 패널 본체
/// (<see cref="DevelopExportPanel"/>)는 붙이기·문구·상태를 맡고, 여기는 컨트롤이 낸 값을
/// 설정으로 옮기기만 합니다 — 한 파일에 다 두면 500 줄을 넘습니다.
/// </summary>
public sealed partial class DevelopExportPanel
{
    private void OnExportFormatChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportFormatSelector.SelectedTag is not string tag ||
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

    private void OnExportTiffCompressionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportTiffCompressionSelector.SelectedTag is not string tag ||
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
    private void OnExportBitDepthChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportBitDepthSelector.SelectedTag is not string tag ||
            !int.TryParse(tag, out int depth))
        {
            return;
        }
        MutateExportSettings(value => value.Format == DevelopExportFormat.Tiff16
            ? value with { TiffBitDepth = depth }
            : value with { PngBitDepth = depth });
    }

    private void OnExportPreserveAlphaToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with
        {
            PreserveAlpha = ExportPreserveAlphaRow.IsOn,
        });
    }

    private void OnExportDpiChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportDpiSelector.SelectedTag is not int dpi)
        {
            return;
        }
        MutateExportSettings(value => value with { Dpi = dpi });
    }

    private void OnExportSizeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportSizeSelector.SelectedTag is not int longEdge)
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

    private void OnExportSharpeningMediumChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportSharpeningMediumSelector.SelectedTag is not string tag ||
            !Enum.TryParse(tag, out OutputSharpeningMedium medium))
        {
            return;
        }
        MutateExportSettings(value => value with { OutputSharpeningMedium = medium });
    }

    private void OnExportMainFlatMasterToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with
        {
            WriteMainFlatMaster = ExportMainFlatMasterRow.IsOn,
        });
    }

    private void OnExportOriginalRawToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with
        {
            WriteOriginalRaw = ExportOriginalRawRow.IsOn,
        });
    }

    private void OnExportSidecarToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        MutateExportSettings(value => value with { WriteSidecar = ExportSidecarRow.IsOn });
    }

    /// <summary>
    /// 게시하는 파일에 무엇을 적을지입니다. 기본은 최소 — 원본이 담고 있던 위치나 장비 정보를
    /// 사용자가 고르지 않았는데 흘려보내지 않습니다.
    /// </summary>
    private void OnExportMetadataPolicyChanged(object? sender, EventArgs args)
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

    private void OnQuickExportFormatChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportFormatSelector.SelectedTag is not string tag ||
            !Enum.TryParse(tag, out DevelopExportFormat format))
        {
            return;
        }
        MutateQuickExportSettings(value => value with { Format = format });
    }

    private void OnQuickExportDpiChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportDpiSelector.SelectedTag is not int dpi)
        {
            return;
        }
        MutateQuickExportSettings(value => value with { Dpi = dpi });
    }

    private void OnQuickExportSizeChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (QuickExportSizeSelector.SelectedTag is not int longEdge)
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
}
