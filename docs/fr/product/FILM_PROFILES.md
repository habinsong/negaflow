# Profils de film

[Accueil de la documentation](../README.md)

Les profils de scanner fournis sont construits à partir de vues de film photographiées par l'auteur du projet, numérisées sur des scanners de laboratoire, puis analysées et enregistrées en JSON.

| Élément | Valeur actuelle |
|---|---:|
| Valeurs par défaut par type de film | 27 |
| Rendus créatifs | 6 |
| Profils de scanner | 15 |
| Observations de bobines | 25 |
| Vues | 928 |
| État de validation | tous `realOnly` |

> [!NOTE]
> `928` est le nombre de vues de film que l'auteur du projet a photographiées et numérisées sur des scanners de laboratoire.

## Trois sortes de données distinctes

| Données | Format | Usage | Nombre |
|---|---|---|---:|
| Type de film | Swift | Dmin/Dmax et valeurs par défaut par type de film | 27 |
| Préréglage de rendu | JSON | Rendus créatifs que vous choisissez | 6 |
| Profil de scanner | JSON | Statistiques relatives de tonalité et de couleur observées sur de vraies numérisations | 15 |

27 noms de film ne font pas 27 profils d'exactitude colorimétrique, et les 6 rendus n'ont rien à voir avec les profils de scanner. La suite ne traite que de la troisième sorte.

## Ce qui est fourni aujourd'hui

`Sources/Chromabase/ScannerProfiles/` contient 15 profils.

<details>
<summary>Voir les 15 profils</summary>

| Scanner | Type de film | Film | Observations de bobines | Vues | État |
|---|---|---|---:|---:|---|
| NORITSU | négatif couleur | Fuji C200 | 3 | 111 | `realOnly` |
| NORITSU | négatif couleur | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| NORITSU | négatif couleur | Kodak Portra 160 | 1 | 37 | `realOnly` |
| NORITSU | négatif couleur | Kodak Portra 400 | 2 | 75 | `realOnly` |
| NORITSU | négatif couleur | Kodak Portra 800 | 1 | 38 | `realOnly` |
| NORITSU | négatif couleur | Kodak Pro Image 100 | 1 | 37 | `realOnly` |
| NORITSU | négatif couleur | Kodak UltraMax 400 | 1 | 38 | `realOnly` |
| NORITSU | négatif couleur | Kodak Vision3 250D | 1 | 37 | `realOnly` |
| NORITSU | négatif couleur | Kodak Vision3 50D | 1 | 38 | `realOnly` |
| NORITSU | diapositive couleur | Kodak Ektachrome 100 | 1 | 38 | `realOnly` |
| NORITSU | diapositive couleur | Kodak Ektachrome 100D | 5 | 181 | `realOnly` |
| SP-3000 | négatif couleur | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| SP-3000 | négatif couleur | Kodak Portra 160 | 1 | 38 | `realOnly` |
| SP-3000 | négatif couleur | Kodak Vision3 250D | 2 | 71 | `realOnly` |
| SP-3000 | diapositive couleur | Kodak Ektachrome 100D | 1 | 37 | `realOnly` |
| **Total** |  |  | **25** | **928** | **15 `realOnly`** |

</details>

25 est la somme des observations de bobines par groupe de profil, pas un nombre de bobines uniques. 928 est le nombre de vues.

## Comment ils sont construits

1. Prise de vue et tri. Les sources sont séparées par scanner, type de film, nom de film et nom de bobine. La rotation et la lecture des fichiers sont confirmées avant l'analyse, et les fichiers vides ou illisibles ne comptent pas.
2. Mesure des vues. Chaque vue reçoit des centiles de luminosité et l'écrêtage aux deux extrémités, les relations entre canaux dans les ombres, les tons moyens et les hautes lumières, la distribution de saturation et de teinte, l'axe neutre Lab des pixels peu saturés, ainsi que le gradient, la netteté et une valeur de référence du grain. Ce sont des observations de scène. L'exposition ou le sujet d'une vue n'est jamais érigé en propriété fixe du scanner.
3. Regroupement des scènes. Les scènes sont groupées par luminosité, contraste, saturation et plage de teintes. Le nombre et la distribution par groupe sont consignés pour qu'un seul type de scène ne domine pas le profil.
4. Vues représentatives. La vue la plus contrastée, la plus nette, celle dont la valeur de grain est la plus élevée et des vues représentant la plage de luminosité et de saturation sont consignées à part, pour qu'une personne puisse retourner à la source.
5. Agrégation par bobine et par groupe. `scripts/compile_scanner_profiles.py` regroupe les données par bobine en groupes film et scanner. Les intervalles vides ne sont pas représentés comme des observations de valeur zéro, et toutes les valeurs doivent être finies, avec de vrais nombres d'échantillons.
6. JSON et empreintes. Le fichier final porte le schéma, l'identifiant, les nombres de sources, les chemins des sources, les statistiques agrégées, l'état de validation et `profileHash`. Le contrôleur vérifie les champs, les nombres, le caractère fini des valeurs, le nom de fichier par rapport à l'identifiant, les nombres de sources et l'empreinte.

## Forme du JSON

<details>
<summary>Exemple de JSON de profil</summary>

```json
{
  "schemaVersion": 2,
  "id": "noritsu__color-nega__kodak-portra-400",
  "displayName": "NORITSU · color nega · Kodak Portra 400",
  "scanner": "NORITSU",
  "kind": "color nega",
  "filmKey": "kodak portra 400",
  "validationStatus": "realOnly",
  "rollCount": 2,
  "imageCount": 75,
  "singleRollLimited": false,
  "sourceProfiles": [],
  "tone": {},
  "color": {},
  "neutralAxis": {},
  "neutralAxisBins": [],
  "hueResponse": [],
  "texture": {},
  "sceneBuckets": [],
  "coverageCandidates": [],
  "profileHash": "sha256:..."
}
```

</details>

## Entrées principales

| Entrée | Contenu | À surveiller |
|---|---|---|
| `tone` | Distribution de luminosité et écrêtage aux deux extrémités | L'exposition d'une vue n'est pas une propriété de la machine |
| `color` | Canaux et saturation dans les ombres, tons moyens et hautes lumières | Une distribution observée, pas une matrice de couleur absolue |
| `neutralAxis` | Lab `a*` et `b*` des pixels peu saturés | Certaines scènes n'ont pas d'objet neutre : les nombres d'échantillons accompagnent la valeur |
| `hueResponse` | Variation de saturation et rotation de teinte par intervalle de teinte | Comparaison relative seulement quand les données des deux machines s'alignent |
| `texture` | Gradient, netteté, valeur de référence du grain | Pas utilisé directement comme valeur d'accentuation de la machine |
| `sceneBuckets` | Statistiques par scène et vues représentatives | Permet de retrouver la source |

L'accentuation du canal de luminosité de la cible `HS` n'est pas une constante de machine mesurée à partir de `texture`, et elle ne synthétise pas de nouveau grain. `SP`, `MAIN` et `PRINT` n'ont pas cette accentuation.

## État des preuves

| État | Signification | Où l'utiliser |
|---|---|---|
| `draft` | Données ou schéma inachevés | Ni pour la livraison ni pour un usage automatique |
| `realOnly` | De vraies numérisations existent, mais pas de matériel de référence distinct | Sélection manuelle seulement, sans affirmation d'exactitude |
| `pairedSmoke` | Un matériel apparié confirme seulement le chemin de traitement | Inutilisable comme preuve de qualité |
| `pairedValidated` | A passé l'étalonnage, le matériel de validation et les contrôles de régression | Sélection automatique permise si la politique l'autorise |

Les 15 profils actuels sont tous `realOnly`. On peut confirmer qu'ils viennent d'observations de matériel réel, pas qu'ils donnent le même résultat que la machine.

Affirmer l'exactitude d'une machine demande davantage de matériel :

- Un identifiant qui confirme qu'il s'agit de la même vue physique
- Un matériel de validation tenu à l'écart de l'étalonnage
- Les conditions de production des images de référence
- Les réglages du scanner et les choix de l'opérateur
- Le lot de la cible, l'éclairage et la méthode de mesure
- Un critère de réussite par image

## Comment l'application les utilise

### Sélection manuelle

Rien n'est sélectionné automatiquement d'après un nom de modèle ou des informations de fichier. Vous choisissez vous-même la cible `HS` ou `SP` et le profil. L'appariement automatique n'est permis que pour `pairedValidated` : il ne concerne donc pas le lot actuel.

### La différence relative entre deux scanners

Les statistiques absolues de scène ne sont pas utilisées telles quelles. Seule la différence entre les groupes correspondants des deux machines est utilisée, de façon limitée :

- L'ensemble épuré des noms de bobines doit concorder.
- Le nombre d'images doit différer de 15 % ou moins.
- Un intervalle de teinte exige des nombres d'échantillons au-dessus du seuil des deux côtés.
- Les valeurs dont le sens s'inverse ne sont pas appliquées.
- Les valeurs entre gains opposés sont calculées dans le domaine logarithmique.
- La tonalité est appliquée une fois à la luminosité gamma Rec.709, et les composantes de couleur Lab sont préservées.

Les profils sources ne portent pas de SHA-256 par vue, et des noms de bobines identiques ne prouvent pas que les mêmes vues ont été appariées.

### Noir et blanc, et positif

En noir et blanc, les composantes de couleur sont écartées et seule la tonalité relative est utilisée. Pour le positif, la luminosité absolue d'une bobine n'est pas reportée sur une autre photographie. Les styles de base de `HS` et `SP` s'appliquent toutefois aux positifs à demi-intensité : le résultat n'est donc pas toujours identique à `MAIN`.

### Texture

Sans matériel apparié sur la même vue, `texture` n'est pas utilisée comme valeur d'accentuation ou de grain propre à une machine. La mise au point, le sujet, le traitement JPEG et les choix de l'opérateur du laboratoire sont tous mêlés à ces chiffres.

## Intégrité des fichiers

`ScannerProfileRegistry` n'ouvre jamais seulement une partie des 15 :

1. Lire le schéma du manifeste.
2. Confirmer que chaque fichier existe et vérifier son SHA-256.
3. Recalculer `profileHash` dans chaque JSON.
4. Vérifier l'identifiant, le nom de fichier, le schéma, l'état, les nombres et le caractère fini des valeurs.
5. Si un seul point diffère, refuser tout le lot.
6. Ne mettre en cache qu'un instantané en lecture seule dont tout concorde.

Le relevé d'export garde l'identifiant et le SHA-256 du profil réellement utilisé.

## Commandes de vérification

À lancer depuis `negaflow-mac/`. La première vérifie le contrat des profils, la deuxième reconstruit les profils, la troisième est le contrôle qualité REAL/TARGET.

```bash
python3 scripts/validate_scanner_profiles.py \
  --mode profile-contract \
  --profiles Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/compile_scanner_profiles.py \
  --source LUT_target/SOURCE \
  --out LUT_target/PROFILES \
  --resource-out Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

Le dépôt ne contient ni manifeste REAL/TARGET ni référence acceptée pour étayer une affirmation de publication. Les tests synthétiques ne confirment que les conditions d'échec du code de contrôle, pas l'exactitude des profils.

## Références

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

Aucun chiffre de profil n'a été pris dans ces sources. Elles ont servi de contexte pour comprendre pourquoi la base du film, la tonalité de la scène et le style de la machine doivent être traités séparément. Les valeurs du JSON viennent du matériel photographié pour ce projet et du code d'analyse du dépôt.

## Code et documents liés

- `Sources/Chromabase/ScannerProfiles/`
- `Sources/Chromabase/Profiles/ScannerProfile/`
- `Sources/Chromabase/Profiles/ScannerTargetGrade/`
- `scripts/compile_scanner_profiles.py`
- `scripts/validate_scanner_profiles.py`
- `scripts/evaluate_profile_quality.py`
- [Contrôle qualité des profils scanner](../reference/PROFILE_QUALITY_GATE.md)
- [Validation colorimétrique IT8](../reference/IT8_COLOR_VALIDATION.md)
- [Chroma Engine](CHROMA_ENGINE.md)
