# Réponse négative

[Accueil de la documentation](../README.md)

## MAIN/PRINT et CS

Par défaut, `MAIN` utilise Équilibre auto sur ON. Le bouton est une petite pastille à droite du titre Cible. Il n’apparaît que pour les négatifs couleur et noir et blanc, avec MAIN (y compris PRINT) et CS. Il ajuste la couleur et la luminosité à partir de la photo actuelle ; OFF saute cette étape. Tonalité auto, balance des blancs auto, niveaux auto et couleur auto restent des fonctions distinctes, désactivées par défaut.

Équilibre auto sur ON rétablit l’inversion MAIN/CS de `412bb31`. Chaque canal mesure sa plage de densité au percentile des 0.2% les plus denses, la limite à 1.8D, puis applique la courbe d’origine `shoulder-print-response-v4` et la correction de saturation des scènes ternes. Les préréglages de film multiplient cette plage par leurs facteurs relatifs par canal. La limite de 1.8D conserve le rendu précédent ; ce n’est pas une propriété mesurée de tous les films. Elle peut affecter les négatifs denses.

OFF utilise la même courbe v4 avec une plage nominale fixe (couleur 1.55D, noir et blanc 2.17D), multipliée par les facteurs du préréglage sélectionné. La normalisation par scène et la correction de saturation sont omises. Pour un négatif couleur, OFF multiplie aussi par une calibration de plage par canal propre au scanner et au film. Elle prend la médiane d'au moins trois images à mesure valide dans le même rouleau (ou, sans rouleau, le même dossier de scan). La valeur choisie reste enregistrée sur chaque image. Avec moins d'images, ou avec des films mélangés, les trois canaux gardent la même plage. À base et réglages identiques, une même transmittance produit le même résultat dans les images d'un même rouleau. ON peut modifier couleur et luminosité selon la scène. Aucun mode ne démontre une précision colorimétrique mesurée du film.

Les mesures de scène sont réutilisées quand seuls les curseurs manuels changent. Windows conserve l’inversion et la saturation D3D pour l’aperçu ; l’export utilise le CPU. Le prototype abandonné à gains médians et ses mesures de vitesse ne décrivent pas cette implémentation. L’inversion RAW précède toujours la matrice couleur de la caméra et les corrections séparées de base du film sont conservées. L’application entière n’a pas été ramenée à `412bb31`.

## Autres cibles et RAW

Les cibles scanner choisies explicitement conservent l’analyse de scène et `shoulder-print-response-v4`. La primitive fixe reste disponible. L’analyse n’utilise plus de plafond universel de 1.8D. Les préréglages de film utilisent des facteurs relatifs fixes sans normaliser chaque image.

Les deux plateformes décodent les RAW de négatifs avec LibRaw, `output_color=0`, un transfert linéaire et des multiplicateurs de canal égaux à 1. La mesure du support et l’inversion utilisent le RGB caméra dématricé ; `rgb_cam` convertit ensuite le positif en sRGB linéaire. La WB de prise de vue, la luminosité automatique et l’ajustement du maximum selon la scène sont désactivés. Aperçus, caches de défauts et exports conservent la matrice différée. Le rendu photo numérique reste séparé. Une sortie caméra non prise en charge produit une erreur. Cet ordre ne remplace pas un étalonnage mesuré caméra/éclairage/film. Le Raw TIFF et le TIFF source avec défauts corrigés sont des images de travail non inversées : la matrice est appliquée à cette sortie.

### RAW avec la CLI hors bundle

L’application inclut le décodeur. Pour la CLI macOS ou les tests hors bundle, compilez la même bibliothèque et fixez son chemin absolu avant le lancement.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Validation et sources

Un recadrage du `Roll_Perforation.tiff` fourni a été comparé au moteur `412bb31` compilé séparément, avec la même base et les mêmes réglages. Les pixels float 32 bits du chemin ON restauré étaient identiques pour MAIN, PRINT, Studio, Emulsion, un préréglage de film et le noir et blanc. Cette comparaison couvre une entrée, pas tous les scans ni les RAW de caméra. `NegativeAutoBalanceTests` vérifie la combinaison d’origine plage/courbe/saturation, OFF et la réutilisation du cache. Windows vérifie le plafond de plage, les facteurs du préréglage, OFF et l’ordre d’inversion RAW sur CPU/D3D.

`FixedNegativeResponseTests` conserve les régressions du modèle v6 utilisé par EXPIRED. Leur variation nulle entre images et leurs résultats avec un modèle direct idéalisé ne valident ni MAIN/CS restauré ni la précision des couleurs d’un film réel. Les identifiants de rendu et de vignette distinguent le résultat restauré des anciens caches.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
