using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Library;

/// <summary>
/// 폴더 머리줄에서 고른 뒤 <b>적용을 누르기 전</b>의 값입니다.
///
/// macOS <c>LibraryFolderDevelopmentControls</c> 는 이것을 컨트롤의 <c>@State</c> 로 들고,
/// 화면이 다시 그려져도 유지하다가 <c>onChange(of: referenceSelection)</c> — 즉 그 폴더의
/// 프레임이 실제로 다른 값이 되었을 때 — 만 다시 맞춥니다.
///
/// Windows 는 고르개가 <c>SelectedIndex="{Binding ProcessIndex}"</c> 로 프레임의 **현재**
/// 값에 묶여 있었습니다. 썸네일 한 장만 도착해도 격자가 다시 투영되고, 그때마다 고른 값이
/// 프레임 값으로 되돌아갔습니다 — 사용자에게는 **"고르고 적용을 눌러도 아무 일이 없다"** 로
/// 보입니다. 초안을 투영 바깥에 두고 고르개가 초안을 보게 해야 macOS 와 같아집니다.
/// </summary>
public sealed class LibraryFolderDevelopmentDrafts
{
    private readonly Dictionary<string, Draft> bySectionId = new(StringComparer.Ordinal);

    private readonly record struct Draft(
        DevelopmentProcess Process,
        DevelopTarget Target,
        DevelopmentProcess ReferenceProcess,
        DevelopTarget ReferenceTarget);

    /// <summary>고른 프로세스를 남깁니다. 타깃 초안은 그대로 둡니다.</summary>
    public void SetProcess(
        string sectionId,
        DevelopmentProcess process,
        DevelopmentProcess referenceProcess,
        DevelopTarget referenceTarget)
    {
        ArgumentNullException.ThrowIfNull(sectionId);
        Draft current = Existing(sectionId, referenceProcess, referenceTarget);
        bySectionId[sectionId] = current with
        {
            Process = process,
            ReferenceProcess = referenceProcess,
            ReferenceTarget = referenceTarget,
        };
    }

    /// <summary>고른 타깃을 남깁니다. 프로세스 초안은 그대로 둡니다.</summary>
    public void SetTarget(
        string sectionId,
        DevelopTarget target,
        DevelopmentProcess referenceProcess,
        DevelopTarget referenceTarget)
    {
        ArgumentNullException.ThrowIfNull(sectionId);
        Draft current = Existing(sectionId, referenceProcess, referenceTarget);
        bySectionId[sectionId] = current with
        {
            Target = target,
            ReferenceProcess = referenceProcess,
            ReferenceTarget = referenceTarget,
        };
    }

    /// <summary>
    /// 이 폴더가 화면에 보여 줄 값입니다. 초안이 있으면 초안이고, 없으면 프레임의 현재 값입니다.
    ///
    /// macOS <c>onChange(of: referenceSelection)</c> 과 같이, 프레임의 값이 초안을 만들 때와
    /// 달라져 있으면 — 즉 다른 곳에서 그 폴더의 사진을 바꿨으면 — 초안을 버리고 새 값을 냅니다.
    /// </summary>
    public (DevelopmentProcess Process, DevelopTarget Target) Resolve(
        string sectionId,
        DevelopmentProcess referenceProcess,
        DevelopTarget referenceTarget)
    {
        ArgumentNullException.ThrowIfNull(sectionId);
        if (!bySectionId.TryGetValue(sectionId, out Draft draft))
        {
            return (referenceProcess, referenceTarget);
        }
        if (draft.ReferenceProcess != referenceProcess || draft.ReferenceTarget != referenceTarget)
        {
            bySectionId.Remove(sectionId);
            return (referenceProcess, referenceTarget);
        }
        return (draft.Process, draft.Target);
    }

    /// <summary>적용이 끝나면 초안은 할 일을 다했습니다.</summary>
    public void Clear(string sectionId)
    {
        ArgumentNullException.ThrowIfNull(sectionId);
        bySectionId.Remove(sectionId);
    }

    private Draft Existing(
        string sectionId,
        DevelopmentProcess referenceProcess,
        DevelopTarget referenceTarget) =>
        bySectionId.TryGetValue(sectionId, out Draft draft) &&
        draft.ReferenceProcess == referenceProcess &&
        draft.ReferenceTarget == referenceTarget
            ? draft
            : new Draft(referenceProcess, referenceTarget, referenceProcess, referenceTarget);
}
