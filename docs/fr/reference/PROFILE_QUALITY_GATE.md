# Contrôle qualité des profils scanner

[Accueil de la documentation](../README.md)

`scripts/evaluate_profile_quality.py` (à lancer depuis `negaflow-mac/`) vérifie si un changement de profil de scanner fait moins bien que la référence acceptée. Il compare deux fichiers `SOURCE/summary.json` produits par `LUT_target/analyze_lut_target.py`, et seuls les cas de validation tenus à l'écart du réglage du profil comptent dans la décision.

L'outil ne définit pas ce qu'est une bonne couleur. Quels chiffres doivent baisser ou monter et quelle variation est acceptable sont inscrits par une personne dans le manifeste du corpus. Il n'y a aucun seuil par défaut.

Ce dépôt ne contient aujourd'hui aucune paire d'images REAL/TARGET (`LUT_target/REAL` et `LUT_target/TARGET` sont vides). Il n'y a donc ni manifeste de corpus réel, ni référence acceptée, ni résultat de réussite sur un vrai appareil. Les tests synthétiques ne vérifient que le code du contrôleur.

> [!WARNING]
> L'exactitude des couleurs d'un scanner ne peut pas être approuvée à partir de ce seul dépôt. Une décision de publication exige des paires REAL/TARGET figées, des cas de validation non utilisés pour le réglage et des tolérances fixées par une personne.

## Jusqu'où l'application utilise les profils actuels

Quand vous choisissez vous-même la cible `HS` ou `SP`, une différence relative limitée issue du groupe `realOnly` fourni peut être utilisée.

Conditions :

- Le type de film et le nom du film concordent.
- L'ensemble épuré des noms de bobines sources concorde.
- Le nombre d'images diffère de 15 % ou moins.

Les profils sources ne portent ni identifiant par vue ni SHA-256, et des noms de bobines identiques ne prouvent pas que les mêmes vues ont été appariées. On ne peut donc pas parler du même résultat que la machine réelle.

Règles d'application :

- Les valeurs de sens opposé entre les deux groupes ne sont pas appliquées.
- En noir et blanc, toutes les composantes de couleur sont écartées et seule la tonalité relative reste.
- La correction relative n'est pas appliquée à un profil de diapositive sans bobine correspondante.
- Sans matériel apparié à la même position, la texture et l'accentuation du scanner ne sont pas appliquées.
- La tonalité est appliquée une fois à la luminosité gamma Rec.709, et les `a*` et `b*` de Lab sont préservés.
- Le gain de couleur est interpolé dans le domaine logarithmique pour que la relation entre ancrages opposés tienne.
- Si le SHA-256 d'un fichier ou du manifeste ne concorde pas, tout le lot de profils est refusé.

## Ce que la documentation des fabricants permet de confirmer

- Le [guide Fujifilm Frontier 570/SP-3000](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf) nomme des fonctions comme le CCD matriciel, Hyper-tone et Hyper-sharpness, mais ne publie ni fonction de transfert ni valeurs de réglage.
- Les [informations produit du Noritsu HS-1800](https://www.noritsu.eu/hardware/noritsu-film-scanner.html) indiquent les formats pris en charge, la résolution et le débit, sans fonction de transfert couleur fixe.
- Le [brevet Noritsu US 7,589,863](https://patents.google.com/patent/US7589863/en) décrit le flux d'un minilab où un opérateur choisit la densité, la gradation et l'accentuation.

Ces documents montrent que le traitement change avec la scène et l'opérateur. Ils ne fournissent aucune constante pour reproduire un HS-1800 ou un SP-3000, et negaflow ne devine pas de telles valeurs d'après un nom de produit.

## Schéma v1 du manifeste de corpus

Le manifeste se place à côté du matériel d'entrée qu'il fige, par exemple `LUT_target/quality/corpus-v1.json`. Les chemins sont relatifs au fichier du manifeste, ou à `--data-root` s'il est donné.

<details>
<summary>Exemple de manifeste</summary>

```json
{
  "schemaVersion": 1,
  "corpusVersion": "scanner-corpus-2026-07-10.1",
  "acceptedBaselineSHA256": "sha256:<64 lowercase hex>",
  "cases": [
    {
      "role": "calibration",
      "stem": "NORITSU/color nega/Portra 400/calibration-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    },
    {
      "role": "holdout",
      "stem": "NORITSU/color nega/Portra 400/holdout-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    }
  ],
  "metrics": [
    {
      "name": "mean_delta_e2000",
      "direction": "lowerIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "similarity_score_0_100",
      "direction": "higherIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "neutral_a_shift",
      "direction": "absoluteLowerIsBetter",
      "allowedRegression": 0.0
    }
  ]
}
```

</details>

Les valeurs `0.0` ne sont pas une recommandation. Réglez les entrées et les tolérances selon votre façon de mesurer et votre politique de publication.

## Règles du manifeste

- `schemaVersion` doit valoir exactement `1`. Les versions inconnues et les champs inconnus sont refusés.
- `corpusVersion` nomme une sélection et un partage figés du matériel.
- `acceptedBaselineSHA256` fige les octets exacts du `summary.json` accepté.
- Chaque cas est `calibration` ou `holdout`. Les noms ne peuvent pas se répéter.
- Le matériel ne peut pas être vide, et les deux rôles exigent au moins un cas.
- Les fichiers REAL et TARGET sont tous deux figés en `sha256:<64 hex minuscules>`.
- Les noms de métriques ne peuvent pas se répéter.
- `allowedRegression` doit être un nombre fini supérieur ou égal à zéro. Les booléens sont refusés.
- Seules les directions `lowerIsBetter`, `higherIsBetter` et `absoluteLowerIsBetter` sont acceptées.

`absoluteLowerIsBetter` compare la distance à zéro. Ne l'employez que lorsque zéro est la référence validée.

## Préparer le candidat et la référence acceptée

```bash
python3 LUT_target/analyze_lut_target.py
```

Avant d'approuver une publication, conservez le `SOURCE/summary.json` complet du candidat comme prochain fichier de référence accepté. Le fichier accepté existant n'est pas écrasé tant que le candidat n'a pas passé la revue. Mettez le SHA-256 exact du fichier accepté dans `acceptedBaselineSHA256`.

Les résumés du candidat et de la référence doivent contenir chaque cas du manifeste exactement une fois. Un cas manquant, un doublon, un échec de traitement ou un cas hors manifeste est une erreur d'entrée.

Les cas `calibration` peuvent servir à ajuster le profil et ne comptent pas dans la décision. Les cas `holdout` restent hors du réglage et de la sélection. Les valeurs de validation sont comparées cas par cas : une moyenne qui s'améliore ne peut pas masquer une image qui se dégrade.

## Exécution

<details open>
<summary>Commande du contrôle qualité</summary>

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

</details>

Modes de vérification des fichiers :

| Valeur | Effet | Utilisable comme preuve de publication |
|---|---|---|
| `all` | Vérifie le chemin et le SHA-256 de chaque fichier REAL/TARGET | Oui |
| `holdout` | Vérifie seulement les fichiers de validation | Pour un diagnostic rapide |
| `none` | Ne vérifie pas les fichiers image | Non |

La valeur par défaut est `all`. Le rapport consigne le mode utilisé, les empreintes du manifeste et des résumés, le résultat de la vérification des fichiers, ainsi que la comparaison par cas et les comptes de l'ensemble de validation. Le même JSON va sur stdout et dans le fichier `--report`, enregistré de façon atomique.

Codes de sortie :

- `0` : l'entrée est valide et rien n'a régressé au-delà de la tolérance
- `1` : l'entrée est valide mais au moins une valeur de validation est sortie de la plage
- `2` : schéma, matériel, empreinte, chemin ou métrique faux ou manquant

## Tester le contrôleur

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

Les tests utilisent des fichiers synthétiques temporaires pour couvrir une comparaison normale, une régression, une empreinte modifiée, un mauvais schéma et de mauvais nombres, des cas en double, manquants ou en échec, et un matériel vide. Ils ne prouvent pas la qualité de la sortie d'un vrai scanner.
