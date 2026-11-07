# Validation colorimétrique IT8

[Accueil de la documentation](../README.md)

L'exactitude des couleurs demande des mesures, pas seulement un examen à l'œil. Une image IT8 est appariée au fichier de référence de sa cible physique, et des résultats chiffrés sont consignés pour chaque plage.

> [!IMPORTANT]
> Le matériel IT8 public permet de confirmer des régressions du contrôleur et du calcul colorimétrique. Il ne peut pas prouver l'exactitude d'un vrai scanner ni d'un film négatif couleur. Juger un appareil exige une cible physique confirmée et des mesures réelles de cet appareil.

## Types de preuve

| Nom | Ce qu'il confirme | Ce qu'il ne confirme pas |
|---|---|---|
| `algorithmRegression` | Lecture des fichiers, conversion ICC, surfaces des plages, Lab, CIEDE2000 | L'exactitude d'un vrai scanner |
| `deviceCharacterization` | Une cible physique confirmée, mesurée sur un vrai appareil | L'exactitude d'une autre cible ou d'un autre appareil |
| `syntheticModel` | L'aller-retour mathématique d'un modèle synthétique indépendant | L'exactitude d'un vrai film ou appareil |

`deviceCharacterization` exige le fabricant, la matière, le numéro de série et le lot de la cible physique. Si l'un d'eux diffère de l'en-tête du fichier de référence, rien n'est évalué.

Les cibles IT8.7/1 et ISO 12641-1 par transmission servent aux originaux positifs par transmission. Leurs résultats ne disent rien du masque orange du négatif couleur, de l'interaction des colorants, de la variation C-41 ni de l'exactitude de sortie du HS et du SP. De telles affirmations exigent un matériel apparié du même négatif couleur passé par les deux chemins, plus un jeu de validation distinct.

La paire publique image/référence FADGI OpenDICE a été mesurée sur 264 plages : ΔE00 médian 9,8815, p95 13,2745, maximum 15,5996. Une conversion LittleCMS indépendante différait de l'évaluateur de 0,105 unité Lab au plus. Ces observations ne passent pas un contrôle d'exactitude pour le film : la numérisation est un IT8 positif, son numéro de série physique n'est pas vérifié et aucune mesure caméra, lumière et film de négatif n'y est jointe.

Des jeux de données publics de négatifs ont aussi été examinés. Les références négatives FADGI ne contiennent que la densité, pas de plages de couleur mesurées. BlueNeg qualifie ses références restaurées de pseudo ground truth. L'étude 2024 du spectrophotomètre ARRI AQUA fournit ses données sur demande, pas en téléchargement libre. Aucun ne donne de référence de couleur de scène indépendante pour l'inversion actuelle.

Une [série d'expositions publique de Kodak ColorPlus 200](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262) (cinq numérisations RAW Sony ILCE-7, de −1 à +3 IL) a aussi été examinée. Sa mire est une Grey White Balance Colour Card : les valeurs de référence X-Rite ont donc été écartées. Aucune des 120 zones de plage échantillonnées n'a atteint zéro ni la pleine échelle dans le RVB d'appareil décodé. C'est un contrôle du signal décodé, pas une mesure directe de la mosaïque du capteur ni un résultat d'exactitude colorimétrique. Sans références mesurées pour cette mire et pour le dispositif de numérisation, on ne peut pas attribuer les dominantes de sortie à l'entrée ou à l'application. Les fichiers restent hors du dépôt, faute de droits de redistribution établis.

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## Matériel de régression public

Ces deux fichiers FADGI/OpenDICE s'utilisent par paire.

- Guide: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- Image: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - Taille: `6255 x 4170`
  - Format: RVB 16 bits avec `Adobe RGB (1998)` intégré
- Fichier de référence: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - Plages: 264 valeurs Lab de `A1` à `L22`
  - Colonne 16 : densité

Les droits de redistribution ne sont pas confirmés : les fichiers restent hors du dépôt et de l'application. Téléchargez-les vous-même et faites pointer le [manifeste d'exemple](../../reference/IT8_FADGI_OPENDICE.example.json) vers eux. Son niveau est `algorithmRegression`, et le renommer en `deviceCharacterization` le fait refuser par le contrôleur. À lancer depuis `negaflow-mac/` :

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## Règles de mesure

- Si le SHA-256 de l'image, du fichier de référence ou de l'ICC choisi diffère du manifeste, l'exécution s'arrête.
- Le rapport v2 consigne aussi le SHA-256 du texte du manifeste.
- `A01` et `A1` lisent les mêmes coordonnées, et l'identifiant d'origine reste dans le rapport.
- Les 60 % centraux de chaque plage de la grille 22 × 12 sont lus à la résolution source en virgule flottante, par lignes `A`–`L` et colonnes `1`–`22`.
- L'ICC intégré est respecté.
- Le calcul va du sRGB linéaire D65 à XYZ, puis par adaptation Bradford à D50, puis à Lab D50/2°.
- Chaque plage consigne sa surface, son nombre de pixels, la moyenne et l'écart type RVB, la proportion écrêtée aux deux extrémités, le nombre de valeurs non finies, le Lab de référence et mesuré, les écarts L/a/b et le CIEDE2000.
- Médiane, p95 et maximum sont des observations, pas un seuil de réussite. Aucun seuil moyen n'est inventé, et `qualityDecision` reste `notEvaluated`.
- Une cible utilisée pour ajuster un profil n'est pas réutilisée pour la validation indépendante.

### Détails de la cible physique

Pour une mesure sur un vrai appareil, l'opérateur relève ces éléments sur l'étiquette de la cible et les note.

<details>
<summary>Exemple de bloc de mesure</summary>

```json
{
  "measurement": {
    "samplerVersion": "center-mean-v1",
    "renderingIntent": "relativeColorimetric",
    "physicalTargetIdentity": {
      "manufacturer": "target label manufacturer",
      "material": "target label material",
      "serial": "target label serial",
      "batchMetadataKey": "PROD_DATE",
      "batchValue": "reference header production date"
    }
  }
}
```

</details>

`MANUFACTURER`, `MATERIAL`, `SERIAL` et l'en-tête de lot (l'un de `BATCH`, `BATCH_ID`, `PROD_DATE`) doivent correspondre au fichier de référence caractère pour caractère. Le `targetID` de premier niveau doit être égal à `serial`, et `batchID` à `batchValue`.

Cet enregistrement montre seulement que ce que l'opérateur a écrit et le fichier de référence concordent. Il ne lit pas l'étiquette sur l'image et ne certifie pas la saisie de l'opérateur. Quand des détails manquent, la date la plus proche ou un fichier de référence générique n'est pas substitué.

Si le fichier de référence porte une information d'illuminant ou d'observateur, elle est comparée au contrat D50/2°, et une contradiction arrête l'exécution. `measurement.renderingIntent` ne peut pas figer directement la conversion Core Image aujourd'hui : le rapport indique donc `manifestDeclarationNotControlledByEvaluator`.

## Sortie `PRINT`

L'IT8.7/1 vise les appareils d'entrée. La sortie imprimante exige un profil ICC RVB d'imprimante construit à partir de mesures réelles de la combinaison imprimante, papier, encre ou chimie, et conditions du pilote ou du procédé.

Ordre des vérifications et de l'usage :

1. Vérifier la taille de l'ICC, la classe d'appareil `prtr`, l'espace de données `RGB `, le PCS Lab/XYZ et la signature `acsp`.
2. Vérifier que ColorSync peut convertir dans les deux sens.
3. À la sélection, figer le nom, la taille en octets et le SHA-256 du profil.
4. L'appliquer une seule fois, à la sortie finale, une fois l'image de travail `MAIN` et la mise en page terminées.
5. Ne pas l'appliquer à `rawScanTIFF` ni à `-main-flat`.
6. Un profil manquant ou erroné échoue avant toute sortie temporaire. Le sRGB ne le remplace pas.

Rien n'affirme que le chemin Core Image et ColorSync actuel fige, bit pour bit sur toutes les versions de macOS, l'intention de rendu et la compensation du point noir.

## Régression synthétique des plages `MAIN`

`NegativeAutoBalanceTests` et `shoulder-print-response-v4`.

MAIN/CS utilise la courbe v4 dans les deux états de l'interrupteur. Les tests v6 conservés vérifient leur propre primitive fixe, et la variation nulle entre vues dans ces tests n'est pas un résultat pour Équilibre auto ON.

[Réponse négative](PRINT_RESPONSE.md)

## Régression de style relatif HS et SP

Un fichier de référence de 264 plages Lab D50, de `A1` à `L22`, est figé par SHA-256. Chaque plage devient un négatif synthétique, puis les chemins `MAIN`, `HS` et `SP` tournent chacun deux fois.

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

Le rapport porte le RVB et le Lab par plage, le `DeltaE00` par rapport à la référence, le `DeltaE00` relatif entre cibles, et des indicateurs d'écrêtage et de valeurs non finies. La monotonie de la rampe neutre se lit dans la colonne de densité `A16...L16`.

Les couleurs qui sortent de 0...1 une fois converties en sRGB linéaire ne peuvent pas être construites exactement comme négatif synthétique ; elles sont donc limitées à la plage affichable. Les statistiques sur une large plage sont ainsi des observations, pas un seuil de réussite.

Le niveau de preuve est toujours `syntheticModel` et la décision toujours `notEvaluated`. Si le manifeste de profil ou le SHA-256 d'un fichier ne concorde pas, l'exécution s'arrête. L'exactitude d'une vraie machine exige des numérisations du même négatif physique sur les deux machines, plus un matériel de validation distinct.

Le D50/2° n'a pas été confirmé d'après l'en-tête du fichier de référence. C'est le contrat propre au banc d'essai pour lire le Lab en D50/2°, d'où `colorimetryInterpretationProvenance` valant `benchmarkContractNotVerifiedFromReferenceHeader`.
