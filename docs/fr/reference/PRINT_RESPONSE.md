# Réponse négative

[Accueil de la documentation](../README.md)

## MAIN/PRINT et CS

Par défaut, la cible est `MAIN` avec Équilibre auto sur ON. L'interrupteur est décrit dans [Chroma Engine](../product/CHROMA_ENGINE.md).

**Équilibre auto ON.** Chaque canal utilise le centile de 0,2 % le plus dense de la scène, avec une limite de plage de 1,8D, suivi de la courbe `shoulder-print-response-v4` et de la vibrance pour scènes ternes. Les préréglages de film multiplient la plage mesurée par leurs facteurs relatifs par canal. La limite de 1,8D est une protection du rendu, pas une propriété mesurée de tous les films, et elle peut jouer sur les négatifs denses.

**Équilibre auto OFF.** La même courbe v4 avec une plage nominale fixe (couleur 1,55D, N&B 2,17D), multipliée par les facteurs du préréglage quand il y en a un. La normalisation de plage par scène et la vibrance pour scènes ternes sont sautées. Pour les négatifs couleur, OFF multiplie aussi par un étalonnage de plage par canal propre au scanner et au film. C'est la médiane d'au moins trois vues à mesure valide, de la même bobine ou, sans bobine, du même dossier de numérisation, et une fois choisie elle reste sur chaque vue. Avec moins de vues, ou avec des films mélangés, les trois canaux gardent la même plage. À transmittance égale, avec la même base et les mêmes réglages, les vues d'une bobine donnent alors le même résultat.

ON peut modifier la luminosité et la couleur selon le contenu de la scène. Aucun des deux modes n'établit une exactitude mesurée des couleurs du film.

Les mesures de scène sont mises en cache pendant que les curseurs manuels bougent. Sous Windows, l'inversion et la vibrance de l'aperçu passent par D3D, l'export par le CPU.

## Autres cibles et RAW

Les cibles de scanner explicites gardent l'analyse de scène et la primitive fixe `shoulder-print-response-v4`. L'analyse de scène n'a pas de plafond de 1,8D universel. Un préréglage de film utilise des facteurs relatifs fixes et ne normalise pas discrètement chaque vue.

Les deux plateformes décodent le RAW d'un négatif avec LibRaw `output_color=0`, transfert linéaire et multiplicateurs de canal unitaires. La mesure de la base et l'inversion se font sur le RVB d'appareil dématricé, puis `rgb_cam` fait passer le positif en sRGB linéaire. La balance des blancs de prise de vue, la luminosité automatique et l'ajustement du maximum selon la scène sont désactivés. L'aperçu, les caches de défauts et l'export gardent la matrice différée. Le rendu des photos numériques est séparé. Une sortie native non prise en charge échoue, au lieu de se rabattre en silence sur un négatif traité par matrice. Cet ordre ne remplace pas un étalonnage mesuré de l'appareil, de la lumière et du film. Les TIFF bruts et les TIFF à source figée sont des images RVB de travail non inversées : leur matrice de couleur est appliquée à cette frontière de sortie.

### Préparer le RAW pour la CLI hors bundle

Le bundle de l'application contient son décodeur. Pour une CLI macOS hors bundle ou pour les tests, compilez la même bibliothèque et indiquez son chemin absolu avant de lancer le processus.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Validation et sources

`NegativeAutoBalanceTests` vérifie la combinaison plage, courbe et vibrance, OFF et la réutilisation du cache. Les tests Windows vérifient le plafond de plage, les facteurs de préréglage, OFF et l'ordre d'inversion RAW CPU/D3D.

`FixedNegativeResponseTests` conserve les régressions du modèle v6 utilisées par EXPIRED. Sa variation nulle entre vues et les couleurs d'un modèle direct idéalisé ne valident ni la réponse MAIN/CS ni l'exactitude des couleurs d'un vrai film. Les identifiants du moteur de rendu et des vignettes séparent les résultats actuels des anciens aperçus en cache.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
