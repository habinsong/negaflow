using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class LibraryFrameCoreJsonReader
{

    /// <summary>
    /// 롤 안의 순번입니다. 이름 짓기에만 쓰이므로, 없거나 모양이 이상하면 읽기를 거부하지 않고
    /// 0 으로 둡니다 — 순번 하나 때문에 사진이 목록에서 사라지는 편이 더 나쁩니다.
    /// </summary>
    internal static int ReadScanIndex(JsonElement frameRecord) =>
        frameRecord.TryGetProperty(ScanIndexName, out JsonElement element) &&
        element.ValueKind == JsonValueKind.Number &&
        element.TryGetInt32(out int scanIndex) &&
        scanIndex > 0
            ? scanIndex
            : 0;

    internal static FrameSourceKind ReadSourceKind(JsonElement frameRecord) =>
        frameRecord.TryGetProperty(SourceKindName, out JsonElement element) &&
        element.ValueKind == JsonValueKind.String &&
        element.GetString() == "scanner"
            ? FrameSourceKind.ScannerTiff
            : FrameSourceKind.ImportedFile;

    /// <summary>
    /// 사본 번호처럼 "있으면 1 이상" 인 값입니다. 모양이 이상하면 없는 것으로 봅니다 — 번호
    /// 하나 때문에 사진이 목록에서 사라지는 편이 더 나쁩니다.
    /// </summary>
    internal static int? ReadOptionalPositiveInt(JsonElement frameRecord, string name) =>
        frameRecord.TryGetProperty(name, out JsonElement element) &&
        element.ValueKind == JsonValueKind.Number &&
        element.TryGetInt32(out int value) &&
        value > 0
            ? value
            : null;

    internal static string? ReadOptionalText(JsonElement frameRecord, string name) =>
        frameRecord.TryGetProperty(name, out JsonElement element) &&
        element.ValueKind == JsonValueKind.String
            ? element.GetString()
            : null;

    /// <summary>
    /// macOS <c>FramePickState</c> 의 raw value 입니다. 키가 없으면 깃발 없음입니다.
    /// </summary>
    internal static bool TryReadPickState(JsonElement frameRecord, out FramePickState pickState)
    {
        pickState = FramePickState.Unflagged;
        if (!frameRecord.TryGetProperty(PickStateName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        switch (element.GetString())
        {
            case "unflagged":
                return true;
            case "picked":
                pickState = FramePickState.Picked;
                return true;
            case "rejected":
                pickState = FramePickState.Rejected;
                return true;
            default:
                return false;
        }
    }

    /// <summary>
    /// 스캔·가져오기 시각입니다. 시간순 정렬에만 씁니다. Swift 는 이 자리를 초 단위 실수로도
    /// 쓰므로 두 형태를 모두 읽습니다. 없는 legacy row 는 null 로 두고 정렬에서 뒤로 보냅니다.
    /// </summary>
    internal static bool TryReadScannedAt(JsonElement frameRecord, out DateTimeOffset? scannedAt)
    {
        scannedAt = null;
        if (!frameRecord.TryGetProperty(ScannedAtName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind == JsonValueKind.String)
        {
            if (!DateTimeOffset.TryParse(
                    element.GetString(),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset parsed))
            {
                return false;
            }
            scannedAt = parsed;
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetDouble(out double seconds) ||
            !double.IsFinite(seconds))
        {
            return false;
        }
        // Swift 의 기준 시각은 2001-01-01 UTC 입니다.
        scannedAt = new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)
            .AddSeconds(seconds);
        return true;
    }

    /// <summary>
    /// macOS 와 같은 0...5 별점입니다. frame record 최상위에 있고, 키가 없는 legacy row 는 0 입니다.
    /// 범위를 벗어난 값은 조용히 자르지 않고 거부합니다 — 카탈로그가 손상됐다는 뜻입니다.
    /// </summary>
    internal static bool TryReadAppliedBase(
        JsonElement frameRecord,
        out ManualBaseRgb? appliedBase)
    {
        appliedBase = null;
        if (!frameRecord.TryGetProperty(BaseRgbName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != 3)
        {
            return false;
        }

        Span<double> channels = stackalloc double[3];
        int index = 0;
        foreach (JsonElement channel in element.EnumerateArray())
        {
            if (channel.ValueKind != JsonValueKind.Number ||
                !channel.TryGetDouble(out double value) ||
                !double.IsFinite(value))
            {
                return false;
            }
            channels[index++] = value;
        }

        appliedBase = new ManualBaseRgb(channels[0], channels[1], channels[2]);
        return true;
    }

    internal static bool TryReadRating(JsonElement frameRecord, out int rating)
    {
        rating = 0;
        if (!frameRecord.TryGetProperty(RatingName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetInt32(out int value) ||
            value is < 0 or > 5)
        {
            return false;
        }
        rating = value;
        return true;
    }


    internal static bool TryReadAppMetadata(
        JsonElement frameRecord,
        out AppMetadataOverlay? overlay)
    {
        overlay = null;
        if (!frameRecord.TryGetProperty(AppMetadataName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadRequiredUInt64(element, AppMetadataRevisionName, out ulong revision) ||
            revision == 0)
        {
            return false;
        }
        if (element.TryGetProperty(AppMetadataVersionName, out JsonElement versionElement) &&
            (versionElement.ValueKind != JsonValueKind.Number ||
                !versionElement.TryGetInt32(out int version) ||
                version != AppMetadataOverlay.CurrentVersion))
        {
            return false;
        }
        if (!TryReadOptionalText(element, AppMetadataTitleName, out string? title) ||
            !TryReadOptionalText(element, AppMetadataCaptionName, out string? caption) ||
            !TryReadOptionalText(element, AppMetadataCopyrightName, out string? copyright) ||
            !TryReadKeywords(element, out IReadOnlyList<string> keywords) ||
            !TryReadFilmShot(element, out FilmShotMetadata? filmShot))
        {
            return false;
        }
        double seconds = 0;
        if (element.TryGetProperty(AppMetadataUpdatedAtName, out JsonElement updatedElement) &&
            (updatedElement.ValueKind != JsonValueKind.Number ||
                !updatedElement.TryGetDouble(out seconds) ||
                !double.IsFinite(seconds)))
        {
            return false;
        }
        AppMetadataOverlay parsed = new()
        {
            Title = title,
            Caption = caption,
            Keywords = keywords,
            Copyright = copyright,
            FilmShot = filmShot,
            Revision = revision,
            UpdatedAt = AppleReferenceDate.AddSeconds(seconds),
        };
        if (!parsed.IsValid)
        {
            return false;
        }
        overlay = parsed;
        return true;
    }

    internal static bool TryReadOptionalText(JsonElement owner, string name, out string? value)
    {
        value = null;
        if (!owner.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        value = element.GetString();
        return true;
    }

    internal static bool TryReadKeywords(JsonElement owner, out IReadOnlyList<string> keywords)
    {
        keywords = [];
        if (!owner.TryGetProperty(AppMetadataKeywordsName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > AppMetadataOverlay.MaximumKeywords)
        {
            return false;
        }
        var read = new List<string>(element.GetArrayLength());
        foreach (JsonElement item in element.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || item.GetString() is not { } keyword)
            {
                return false;
            }
            read.Add(keyword);
        }
        keywords = read;
        return true;
    }

    internal static bool TryReadFilmShot(JsonElement owner, out FilmShotMetadata? filmShot)
    {
        filmShot = null;
        if (!owner.TryGetProperty(FilmShotName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadOptionalText(element, FilmShotCameraMakeName, out string? cameraMake) ||
            !TryReadOptionalText(element, FilmShotCameraModelName, out string? cameraModel) ||
            !TryReadOptionalText(element, FilmShotLensModelName, out string? lensModel) ||
            !TryReadOptionalText(element, FilmShotFilmStockName, out string? filmStock) ||
            !TryReadOptionalInt(element, FilmShotIsoSpeedName, out int? isoSpeed) ||
            !TryReadOptionalDouble(element, FilmShotExposureTimeName, out double? exposure) ||
            !TryReadOptionalDouble(element, FilmShotFNumberName, out double? fNumber) ||
            !TryReadOptionalDouble(element, FilmShotFocalLengthName, out double? focalLength))
        {
            return false;
        }
        FilmShotMetadata parsed = new(
            cameraMake, cameraModel, lensModel, filmStock,
            isoSpeed, exposure, fNumber, focalLength);
        if (parsed.IsEmpty || !parsed.IsValid)
        {
            return false;
        }
        filmShot = parsed;
        return true;
    }

    internal static bool TryReadOptionalInt(JsonElement owner, string name, out int? value)
    {
        value = null;
        if (!owner.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetInt32(out int parsed))
        {
            return false;
        }
        value = parsed;
        return true;
    }

    internal static bool TryReadOptionalDouble(JsonElement owner, string name, out double? value)
    {
        value = null;
        if (!owner.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetDouble(out double parsed) ||
            !double.IsFinite(parsed))
        {
            return false;
        }
        value = parsed;
        return true;
    }

    internal static bool TryReadSourceMetadata(
        JsonElement frameRecord,
        out LibrarySourceMetadata? sourceMetadata)
    {
        sourceMetadata = null;
        if (!frameRecord.TryGetProperty(SourceMetadataName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadRequiredUInt64(element, SourceFileBytesName, out ulong fileBytes) ||
            !TryReadRequiredUInt32(element, SourcePixelWidthName, out uint pixelWidth) ||
            !TryReadRequiredUInt32(element, SourcePixelHeightName, out uint pixelHeight) ||
            !TryReadRequiredUInt16(element, SourceSamplesPerPixelName, out ushort samplesPerPixel) ||
            !TryReadRequiredUInt16(element, SourceBitsPerSampleName, out ushort bitsPerSample) ||
            !TryReadRequiredUInt16(element, SourceSampleFormatName, out ushort sampleFormat) ||
            !TryReadRequiredUInt16(element, SourceOrientationName, out ushort orientation))
        {
            return false;
        }
        LibrarySourceMetadata parsed = new(
            fileBytes, pixelWidth, pixelHeight, samplesPerPixel, bitsPerSample, sampleFormat,
            orientation);
        if (!parsed.IsValid)
        {
            return false;
        }
        sourceMetadata = parsed;
        return true;
    }

    internal static bool TryReadRequiredUInt64(JsonElement owner, string name, out ulong value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt64(out value);
    }

    internal static bool TryReadRequiredUInt32(JsonElement owner, string name, out uint value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt32(out value);
    }

    internal static bool TryReadRequiredUInt16(JsonElement owner, string name, out ushort value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt16(out value);
    }

    internal static bool TryReadInfraredPath(
        JsonElement frameRecord,
        string sourcePath,
        out string? infraredPath)
    {
        infraredPath = null;
        if (!frameRecord.TryGetProperty(InfraredPathName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String ||
            element.GetString() is not { Length: > 0 } path ||
            string.IsNullOrWhiteSpace(path) ||
            !Path.IsPathFullyQualified(path))
        {
            return false;
        }
        try
        {
            if (string.Equals(
                    Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)),
                    Path.TrimEndingDirectorySeparator(Path.GetFullPath(sourcePath)),
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
        infraredPath = path;
        return true;
    }

}
