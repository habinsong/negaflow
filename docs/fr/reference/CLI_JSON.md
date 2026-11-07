# JSON de la CLI scanner

[Accueil de la documentation](../README.md)

Les scripts et les autres applications lisent les informations du scanner dans ce JSON. La CLI se contente de sérialiser les informations d'appareil et les capacités reçues par `ScannerKit`.

| Élément | Contrat |
|---|---|
| Commandes | `detect --json`, `capabilities <scannerID> --json` |
| stdout | Un document JSON et un saut de ligne final |
| stderr | Journal de diagnostic |
| Schéma | `negaflow.scanner-cli`, version `1` |

## Commandes

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json` ne fonctionne que sur ces deux commandes en lecture seule. Sur `scan` ou `develop`, il se termine par l'erreur `unsupported_json_command`.

## Forme commune

Succès comme échec écrivent un document JSON sur stdout.

<details>
<summary>Exemple de réponse réussie</summary>

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

En cas d'échec, `status` vaut `error` et `payload` vaut `null`. `error` contient un code stable lisible par machine et une description. Les journaux et la progression vont uniquement sur stderr.

## Informations de capacités

Le `payload` de `capabilities` contient toujours tous ces champs :

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

Une valeur que l'appareil n'a pas signalée n'est pas devinée. Elle devient `null`, un tableau vide, `false` ou les `disabledReasons` envoyés par le module.

`estimatedScanSpeeds` est un tableau de cet objet, trié par DPI croissant :

```json
{ "dpi": 3600, "seconds": 42.0 }
```

L'application et la CLI lisent les mêmes `ScannerCapabilities`. Un contrôle de cohérence vérifie que les commandes affichées suivent les champs JSON.

## Règles de version

- Le sens et le type d'un champ existant ne changent pas.
- Un nouveau champ facultatif n'est ajouté que si les anciens programmes peuvent l'ignorer.
- Supprimer, renommer ou changer le type d'un champ augmente `schemaVersion`.
- Résolutions, modes et profondeurs gardent l'ordre du module. Seules les vitesses estimées sont triées.
