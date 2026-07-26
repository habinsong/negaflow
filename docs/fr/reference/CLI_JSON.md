# JSON de la CLI scanner

[Accueil de la documentation](../README.md)

C'est la forme dans laquelle un script ou une autre application lit les informations du scanner.
Elle reste séparée de l'implémentation du scanner.
La CLI se contente de convertir en JSON les informations et capacités reçues par `ScannerKit`.

| Élément | Contrat |
|---|---|
| Commandes prises en charge | `detect --json`, `capabilities <scannerID> --json` |
| stdout | Un document JSON et un saut de ligne final |
| stderr | Journal de diagnostic |
| Schéma actuel | `negaflow.scanner-cli`, version `1` |

## Commandes

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

Pour l'instant, `--json` ne fonctionne que sur ces deux commandes en lecture seule.
Ajoutez-le à `scan` ou `develop`, qui modifient des fichiers ou émettent une progression,
et cela se termine par une erreur `unsupported_json_command`.

## Forme commune

Succès comme échec écrivent un seul document JSON sur stdout, avec un saut de ligne à la fin.

<details>
<summary>Exemple de réponse en cas de succès</summary>

```json
{
  "schema": "negaflow.scanner-cli",
  "schemaVersion": 1,
  "command": "capabilities",
  "status": "ok",
  "payload": {},
  "error": null
}
```

</details>

En cas d'échec, `status` vaut `error` et `payload` vaut `null`.
`error` porte un code machine qui ne change pas et une description destinée aux humains.
Les journaux de diagnostic partent sur stderr.
Journaux et progression ne sont jamais mêlés à stdout.

## Informations de capacités

Le `payload` de `capabilities` porte toujours tous ces champs.

- `resolutionsDPI`, `modes`, `bitDepths`
- `sourceModes`, `transparencyModes`
- `supportsPreview`, `supportsTransparency`, `supportsInfrared`
- `supportsMultiExposure`, `supportsScanArea`, `supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`, `contrastRange`, `hardwareExposureRange`
- `scanOriginXRange`, `scanOriginYRange`, `scanWidthRange`, `scanHeightRange`
- `disabledReasons`
- `minScanArea`, `maxScanArea`, `scanAreaUnit`
- `outputFormats`, `estimatedScanSpeeds`

Les valeurs que l'appareil n'a pas signalées ne sont pas devinées.
Selon le cas, on utilise `null`, un tableau vide, `false`,
ou les `disabledReasons` envoyés par le plugin.

`estimatedScanSpeeds` est un tableau de cet objet, trié par DPI croissants.

```json
{ "dpi": 3600, "seconds": 42.0 }
```

L'écran de l'application et la CLI lisent les mêmes `ScannerCapabilities`.
Le contrôle de cohérence confirme que les commandes ouvertes à l'écran suivent les mêmes valeurs que
les champs JSON.

## Règles de version

- Le sens et le type d'un champ existant ne changent pas.
- Un nouveau champ facultatif n'arrive que si les programmes plus anciens peuvent ignorer les champs inconnus.
- Supprimer un champ, le renommer ou changer son type fait monter `schemaVersion`.
- Résolutions, modes et profondeurs de bits gardent l'ordre du plugin.
- Seules les vitesses estimées sont triées par DPI.
