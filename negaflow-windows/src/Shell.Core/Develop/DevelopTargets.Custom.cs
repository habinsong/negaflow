using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

public enum DevelopTargetFamily { Main, Noritsu, Sp3000, F135, Hr, Custom }
public sealed record CustomTargetChoice(DevelopTarget Target, string Id, string Name);

public static partial class DevelopTargets
{
    public static IReadOnlyList<DevelopTargetFamily> Families { get; } = Enum.GetValues<DevelopTargetFamily>();
    public static IReadOnlyList<CustomTargetChoice> CustomChoices { get; } =
    [
        new(DevelopTarget.Emulsion, "emulsion", "Emulsion"),
        new(DevelopTarget.Reversal, "reversal", "Reversal"),
        new(DevelopTarget.DyeTransfer, "dye-transfer", "Dye Transfer"),
        new(DevelopTarget.SkipBleach, "skip-bleach", "Skip Bleach"),
        new(DevelopTarget.PlateGlass, "plate-glass", "Plate Glass"),
        new(DevelopTarget.AmberGlass, "amber-glass", "Amber Glass"),
        new(DevelopTarget.Ultramarine, "ultramarine", "Ultramarine"),
        new(DevelopTarget.Terracotta, "terracotta", "Terracotta"),
        new(DevelopTarget.Celadon, "celadon", "Celadon"),
        new(DevelopTarget.Nacre, "nacre", "Nacre"),
        new(DevelopTarget.Dichroic, "dichroic", "Dichroic"),
        new(DevelopTarget.Wetzlar, "wetzlar", "Wetzlar"),
        new(DevelopTarget.Classic, "classic", "Classic"),
        new(DevelopTarget.Studio, "studio", "Studio"),
        new(DevelopTarget.Rochester, "rochester", "Rochester"),
        new(DevelopTarget.SlideShow, "slide-show", "Slide Show"),
        new(DevelopTarget.Cinema, "cinema", "Cinema"),
        new(DevelopTarget.PointAndShoot, "point-and-shoot", "Point & Shoot"),
    ];
    public static IReadOnlyList<DevelopTarget> Custom { get; } = [.. CustomChoices.Select(x => x.Target)];
    public static IReadOnlyList<IReadOnlyList<DevelopTarget>> CustomGroups { get; } =
    [Custom.Take(11).ToArray(), Custom.Skip(11).Take(4).ToArray(), Custom.Skip(15).ToArray()];
    public static IReadOnlyList<IReadOnlyList<DevelopTarget>> CustomRows { get; } =
        [.. CustomGroups.SelectMany(group => group.Chunk(2).Select(row => (IReadOnlyList<DevelopTarget>)row))];

    public static bool IsCustom(DevelopTarget target) => target >= DevelopTarget.Emulsion && target <= DevelopTarget.PointAndShoot;
    public static string? CustomName(DevelopTarget target) => CustomChoices.FirstOrDefault(x => x.Target == target)?.Name;
    public static string? CustomId(DevelopTarget target) => CustomChoices.FirstOrDefault(x => x.Target == target)?.Id;
    public static DevelopTargetFamily CapsuleFamily(DevelopTarget target) => target switch
    {
        DevelopTarget.Noritsu => DevelopTargetFamily.Noritsu,
        DevelopTarget.Sp3000 => DevelopTargetFamily.Sp3000,
        DevelopTarget.F135 => DevelopTargetFamily.F135,
        DevelopTarget.Hr => DevelopTargetFamily.Hr,
        _ => IsCustom(target) ? DevelopTargetFamily.Custom : DevelopTargetFamily.Main,
    };
    public static DevelopTarget TargetForFamily(DevelopTargetFamily family, DevelopTarget current) => family switch
    {
        DevelopTargetFamily.Main => DevelopTarget.Main,
        DevelopTargetFamily.Noritsu => DevelopTarget.Noritsu,
        DevelopTargetFamily.Sp3000 => DevelopTarget.Sp3000,
        DevelopTargetFamily.F135 => DevelopTarget.F135,
        DevelopTargetFamily.Hr => DevelopTarget.Hr,
        DevelopTargetFamily.Custom => IsCustom(current) ? current : DevelopTarget.Emulsion,
        _ => throw new ArgumentOutOfRangeException(nameof(family)),
    };
    public static string FamilyName(DevelopTargetFamily family) => family == DevelopTargetFamily.Custom
        ? "CS" : DisplayName(TargetForFamily(family, DevelopTarget.Main));

    public static DevelopTarget MoveCustomSelection(DevelopTarget target, int horizontal, int vertical)
    {
        for (int row = 0; row < CustomRows.Count; ++row)
        {
            int column = CustomRows[row].ToList().IndexOf(target);
            if (column < 0) { continue; }
            int nextRow = Math.Clamp(row + vertical, 0, CustomRows.Count - 1);
            int nextColumn = Math.Clamp(column + horizontal, 0, CustomRows[nextRow].Count - 1);
            return CustomRows[nextRow][nextColumn];
        }
        return target;
    }
}
