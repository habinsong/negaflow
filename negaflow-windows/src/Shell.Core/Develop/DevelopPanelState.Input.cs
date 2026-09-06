using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed partial class DevelopPanelState
{
    private readonly DevelopBaseReferenceState baseReference = new();
    public ManualBaseRgb? LastReferenceBase => baseReference.Value;
    public double BaseScale => SelectedFrame?.Base.Scale ?? 1.0;

    public LibraryFrameError SetBaseScale(double scale) =>
        RefreshAfterEdit(baseEditor.SetScale(SelectedFrame, scale));

    public LibraryFrameError SetPickedBase(double red, double green, double blue) =>
        RefreshAfterEdit(baseEditor.SetManualBase(SelectedFrame, red, green, blue, resetScale: true));

    private void BindReferenceInput(LibraryFrameSnapshot? frame) => baseReference.Bind(frame);
}
