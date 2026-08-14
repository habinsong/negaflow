namespace Negaflow.Shell.Develop;

/// <summary>
/// 이름 붙여 담아 둔 내보내기 설정입니다. macOS <c>ExportRecipe</c> 와 같이 형식·인코딩·크기·
/// 선명도와 사이드카 여부까지 한 벌로 담고, 목적지 폴더와 파일명 패턴은 담지 않습니다 —
/// 그것은 이번 작업의 자리이지 설정의 성질이 아닙니다.
/// </summary>
public sealed record ExportRecipe(string Id, string Name, ExportSettings Settings)
{
    public const int MaximumRecipes = 64;

    public static string? NormalizeName(string? value) =>
        Negaflow.Catalog.AppMetadataOverlay.NormalizeText(value);

    /// <summary>담을 때 목적지를 떼어냅니다.</summary>
    public static ExportSettings Strip(ExportSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return settings.Normalize() with
        {
            FolderPath = string.Empty,
            NamingTemplate = ExportNamingTemplate.DefaultPattern,
            SequenceStart = 1,
        };
    }

    /// <summary>
    /// 담아 둔 설정을 지금 설정에 얹습니다. 목적지와 파일명 패턴은 지금 것을 지킵니다 — 프리셋을
    /// 고르는 것이 내보낼 폴더를 바꾸는 뜻은 아닙니다.
    /// </summary>
    public ExportSettings ApplyTo(ExportSettings current)
    {
        ArgumentNullException.ThrowIfNull(current);
        return Settings.Normalize() with
        {
            FolderPath = current.FolderPath,
            NamingTemplate = current.NamingTemplate,
            SequenceStart = current.SequenceStart,
        };
    }
}

/// <summary>담아 둔 설정 목록입니다. 셸 설정 파일에 삽니다.</summary>
public sealed record ExportRecipeLibrary
{
    public IReadOnlyList<ExportRecipe> Recipes { get; init; } = [];

    public string? SelectedId { get; init; }

    public ExportRecipeLibrary Normalize()
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var kept = new List<ExportRecipe>();
        foreach (ExportRecipe recipe in Recipes ?? [])
        {
            if (recipe is null ||
                ExportRecipe.NormalizeName(recipe.Name) is not { } name ||
                string.IsNullOrWhiteSpace(recipe.Id) ||
                !seen.Add(recipe.Id))
            {
                continue;
            }
            kept.Add(recipe with { Name = name, Settings = ExportRecipe.Strip(recipe.Settings) });
            if (kept.Count == ExportRecipe.MaximumRecipes)
            {
                break;
            }
        }
        return new ExportRecipeLibrary
        {
            Recipes = kept,
            // 목록에 없는 선택은 빈 선택입니다. 없는 프리셋을 고른 것으로 보여 주면 사용자는
            // 적용됐다고 읽습니다.
            SelectedId = kept.Any(recipe =>
                string.Equals(recipe.Id, SelectedId, StringComparison.Ordinal))
                ? SelectedId
                : null,
        };
    }

    public ExportRecipe? Selected =>
        Recipes.FirstOrDefault(recipe =>
            string.Equals(recipe.Id, SelectedId, StringComparison.Ordinal));

    /// <summary>지금 설정을 이름 붙여 담습니다. 같은 이름이 있으면 덮어씁니다.</summary>
    public ExportRecipeLibrary Save(string name, ExportSettings settings)
    {
        if (ExportRecipe.NormalizeName(name) is not { } normalized)
        {
            return this;
        }
        var recipes = new List<ExportRecipe>(Recipes);
        int existing = recipes.FindIndex(recipe =>
            string.Equals(recipe.Name, normalized, StringComparison.Ordinal));
        ExportSettings stripped = ExportRecipe.Strip(settings);
        if (existing >= 0)
        {
            recipes[existing] = recipes[existing] with { Settings = stripped };
            return (this with { Recipes = recipes, SelectedId = recipes[existing].Id }).Normalize();
        }
        ExportRecipe created = new(Guid.NewGuid().ToString("D"), normalized, stripped);
        recipes.Add(created);
        return (this with { Recipes = recipes, SelectedId = created.Id }).Normalize();
    }

    public ExportRecipeLibrary Rename(string recipeId, string name)
    {
        if (ExportRecipe.NormalizeName(name) is not { } normalized)
        {
            return this;
        }
        var recipes = new List<ExportRecipe>(Recipes);
        int index = recipes.FindIndex(recipe =>
            string.Equals(recipe.Id, recipeId, StringComparison.Ordinal));
        if (index < 0)
        {
            return this;
        }
        recipes[index] = recipes[index] with { Name = normalized };
        return (this with { Recipes = recipes }).Normalize();
    }

    public ExportRecipeLibrary Delete(string recipeId)
    {
        var recipes = new List<ExportRecipe>(Recipes);
        if (recipes.RemoveAll(recipe =>
                string.Equals(recipe.Id, recipeId, StringComparison.Ordinal)) == 0)
        {
            return this;
        }
        return (this with { Recipes = recipes, SelectedId = null }).Normalize();
    }

    /// <summary>macOS 처럼 "내보내기 설정 N" 으로 비어 있는 번호를 찾습니다.</summary>
    public int NextDefaultIndex()
    {
        for (int index = 1; index <= ExportRecipe.MaximumRecipes + 1; ++index)
        {
            if (!Recipes.Any(recipe => recipe.Name.EndsWith(
                    " " + index.ToString(System.Globalization.CultureInfo.CurrentCulture),
                    StringComparison.Ordinal)))
            {
                return index;
            }
        }
        return Recipes.Count + 1;
    }
}
