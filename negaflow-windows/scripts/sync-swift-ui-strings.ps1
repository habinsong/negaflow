param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
$mappingPath = Join-Path $windowsRoot "baseline/swift-ui-string-map.json"
$shellRoot = Join-Path $windowsRoot "src/Shell"

$languages = @(
    @{ Tag = "en-US"; Suffix = "English"; Accessibility = "english" },
    @{ Tag = "ko-KR"; Suffix = "Korean"; Accessibility = "korean" },
    @{ Tag = "ja-JP"; Suffix = "Japanese"; Accessibility = "japanese" },
    @{ Tag = "zh-Hans"; Suffix = "SimplifiedChinese"; Accessibility = "simplifiedChinese" },
    @{ Tag = "fr-FR"; Suffix = "French"; Accessibility = "french" },
    @{ Tag = "de-DE"; Suffix = "German"; Accessibility = "german" }
)

$mapping = Get-Content -LiteralPath $mappingPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($mapping.schemaVersion -ne 1) {
    throw "Unsupported UI string mapping schema: $($mapping.schemaVersion)"
}

function ConvertFrom-SwiftStringLiteral {
    param([Parameter(Mandatory)][string]$Value)

    return [System.Text.RegularExpressions.Regex]::Unescape($Value)
}

function Get-SwiftTableValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key
    )

    $source = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    $escapedKey = [regex]::Escape($Key)
    $pattern = '(?m)^\s*\.' + $escapedKey + '\s*:\s*"(?<value>(?:\\.|[^"\\])*)"'
    $match = [regex]::Match($source, $pattern)
    if (-not $match.Success) {
        throw "Swift localization value not found: $Key in $Path"
    }

    return ConvertFrom-SwiftStringLiteral $match.Groups["value"].Value
}

function Get-SwiftAccessibilityValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Language,
        [Parameter(Mandatory)][string]$Key
    )

    $source = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    $escapedLanguage = [regex]::Escape($Language)
    $blockPattern = '(?ms)^\s*\.' + $escapedLanguage + '\s*:\s*\[(?<body>.*?)^\s*\](?:,|\s*$)'
    $block = [regex]::Match($source, $blockPattern)
    if (-not $block.Success) {
        throw "Swift accessibility language block not found: $Language"
    }

    $escapedKey = [regex]::Escape($Key)
    $valuePattern = '\.' + $escapedKey + '\s*:\s*"(?<value>(?:\\.|[^"\\])*)"'
    $match = [regex]::Match($block.Groups["body"].Value, $valuePattern)
    if (-not $match.Success) {
        throw "Swift accessibility value not found: $Language.$Key"
    }

    return ConvertFrom-SwiftStringLiteral $match.Groups["value"].Value
}

function Escape-XmlText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    return [System.Security.SecurityElement]::Escape($Value)
}

function New-ResourcesDocument {
    param(
        [Parameter(Mandatory)][hashtable]$Values
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<root>')
    $lines.Add('  <xsd:schema id="root" xmlns="" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">')
    $lines.Add('    <xsd:element name="root" msdata:IsDataSet="true">')
    $lines.Add('      <xsd:complexType>')
    $lines.Add('        <xsd:choice maxOccurs="unbounded">')
    $lines.Add('          <xsd:element name="data">')
    $lines.Add('            <xsd:complexType>')
    $lines.Add('              <xsd:sequence>')
    $lines.Add('                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />')
    $lines.Add('                <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />')
    $lines.Add('              </xsd:sequence>')
    $lines.Add('              <xsd:attribute name="name" type="xsd:string" msdata:Ordinal="1" />')
    $lines.Add('              <xsd:attribute name="type" type="xsd:string" msdata:Ordinal="3" />')
    $lines.Add('              <xsd:attribute name="mimetype" type="xsd:string" msdata:Ordinal="4" />')
    $lines.Add('            </xsd:complexType>')
    $lines.Add('          </xsd:element>')
    $lines.Add('          <xsd:element name="resheader">')
    $lines.Add('            <xsd:complexType>')
    $lines.Add('              <xsd:sequence>')
    $lines.Add('                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />')
    $lines.Add('              </xsd:sequence>')
    $lines.Add('              <xsd:attribute name="name" type="xsd:string" use="required" />')
    $lines.Add('            </xsd:complexType>')
    $lines.Add('          </xsd:element>')
    $lines.Add('        </xsd:choice>')
    $lines.Add('      </xsd:complexType>')
    $lines.Add('    </xsd:element>')
    $lines.Add('  </xsd:schema>')
    $lines.Add('  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>')
    $lines.Add('  <resheader name="version"><value>1.3</value></resheader>')
    $lines.Add('  <resheader name="reader"><value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=2.0.3500.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>')
    $lines.Add('  <resheader name="writer"><value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=2.0.3500.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>')

    foreach ($name in ($Values.Keys | Sort-Object)) {
        $entry = $Values[$name]
        $lines.Add(('  <data name="{0}" xml:space="preserve">' -f (Escape-XmlText $name)))
        $lines.Add(('    <value>{0}</value>' -f (Escape-XmlText $entry.Value)))
        $lines.Add(('    <comment>{0}</comment>' -f (Escape-XmlText $entry.Source)))
        $lines.Add('  </data>')
    }

    $lines.Add('</root>')
    return ($lines -join "`n") + "`n"
}

$accessibilityPath = Join-Path $repositoryRoot "Sources/negaflowApp/Localization/AppLocalization+Accessibility.swift"
$changed = $false
foreach ($language in $languages) {
    $values = @{}
    foreach ($domainProperty in $mapping.domains.PSObject.Properties) {
        $domain = $domainProperty.Name
        foreach ($entry in $domainProperty.Value) {
            if ($domain -eq "AppLocalizedText") {
                $sourcePath = Join-Path $repositoryRoot (
                    "Sources/negaflowApp/Localization/Core/Tables/AppLocalizedText+{0}.swift" -f $language.Suffix)
                $value = Get-SwiftTableValue -Path $sourcePath -Key $entry.key
            }
            elseif ($domain -eq "AppLocalizedPhrase") {
                $sourcePath = Join-Path $repositoryRoot (
                    "Sources/negaflowApp/Localization/Phrases/Tables/AppLocalizedPhrase+{0}.swift" -f $language.Suffix)
                $value = Get-SwiftTableValue -Path $sourcePath -Key $entry.key
            }
            elseif ($domain -eq "AppAccessibilityPhrase") {
                $value = Get-SwiftAccessibilityValue `
                    -Path $accessibilityPath `
                    -Language $language.Accessibility `
                    -Key $entry.key
            }
            else {
                throw "Unsupported localization domain: $domain"
            }

            foreach ($property in $entry.properties) {
                $resourceName = "$($entry.key).$property"
                if ($values.ContainsKey($resourceName)) {
                    throw "Duplicate resource mapping: $resourceName"
                }

                $values[$resourceName] = @{
                    Value = $value
                    Source = "$domain.$($entry.key)"
                }
            }
        }
    }

    $document = New-ResourcesDocument -Values $values
    $outputDirectory = Join-Path $shellRoot "Strings/$($language.Tag)"
    $outputPath = Join-Path $outputDirectory "Resources.resw"
    $existing = if (Test-Path -LiteralPath $outputPath) {
        [System.IO.File]::ReadAllText($outputPath, [System.Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n")
    } else {
        $null
    }

    if ($existing -ne $document) {
        if ($Check) {
            throw "Generated UI resources are stale: $outputPath"
        }

        [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
        [System.IO.File]::WriteAllText($outputPath, $document, [System.Text.UTF8Encoding]::new($false))
        $changed = $true
    }
}

[pscustomobject]@{
    status = "ok"
    operation = if ($Check) { "check_swift_ui_strings" } else { "sync_swift_ui_strings" }
    languages = $languages.Count
    changed = $changed
} | ConvertTo-Json -Compress
