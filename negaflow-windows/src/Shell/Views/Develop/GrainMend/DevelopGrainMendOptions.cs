using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>프레임별 민감도와 미세 반점 기본값입니다. 검출 실행과 다른 이유입니다.</summary>
internal sealed class DevelopGrainMendOptions
{
    private readonly DevelopGrainMendPanel view;

    internal DevelopGrainMendOptions(DevelopGrainMendPanel view) => this.view = view;

    internal double GetSensitivity(bool automatic)
    {
        return view.panel?.SelectedFrame is { } frame
            ? view.grainMend.Sensitivity(frame.Id, automatic)
            : GrainMendSensitivity.Default;
    }

    internal void SetSensitivity(bool automatic, double value)
    {
        if (view.panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        view.grainMend.SetSensitivity(frame.Id, automatic, value);
    }

    internal bool GetMicroSpecks(bool automatic)
    {
        return view.panel?.SelectedFrame is { } frame
            ? view.grainMend.MicroSpecks(
                frame.Id,
                automatic,
                MicroSpeckDefault(automatic: true),
                MicroSpeckDefault(automatic: false))
            : MicroSpeckDefault(automatic);
    }

    /// <summary>설정에 담긴 기본값입니다. 설정을 못 읽으면 macOS 기본인 켬입니다.</summary>
    internal bool MicroSpeckDefault(bool automatic) =>
        view.workspaceState?.Current is { } preferences
            ? automatic
                ? preferences.AutoDefectDetectsMicroSpecks
                : preferences.GuidedDefectDetectsMicroSpecks
            : true;

    internal void SetMicroSpecks(bool automatic, bool enabled)
    {
        if (view.panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        view.grainMend.SetMicroSpecks(
            frame.Id,
            automatic,
            enabled,
            MicroSpeckDefault(automatic: true),
            MicroSpeckDefault(automatic: false));
    }
}
