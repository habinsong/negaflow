namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 화면이 파일을 쓰는 중인지입니다. 진단 패널의 카탈로그 수동 복구·재설치가 이 동안
/// 기다립니다(macOS <c>isPrintPackageExporting</c>).
/// </summary>
public sealed partial class PrintWorkspaceView
{
    internal bool IsSheetExportRunning => printSheetExport?.IsRunning == true;
}
