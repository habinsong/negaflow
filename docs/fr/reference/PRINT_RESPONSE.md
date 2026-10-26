# Réponse négative fixe

[Accueil de la documentation](../README.md)

## MAIN/PRINT et cibles dérivées

`fixed-density-linear-v6` traite les négatifs `MAIN/PRINT` sans profil de scanner. Les valeurs de correction sont fixes. À base et réglages identiques, les pixels voisins, le recadrage et l’histogramme ne changent pas l’inversion d’une même transmittance. Aucune vibrance liée à la scène n’est appliquée.

Les cibles personnalisées et EXPIRED utilisent la même inversion fixe que MAIN. La couleur personnalisée est appliquée après la calibration. EXPIRED ne corrige que si les critères de preuve sont remplis ; sans preuve admissible, sa sortie est identique à MAIN. Ces cibles ignorent un ancien profil scanner.

`B` est la transmittance mesurée du support. `f` vaut 1 pour la réponse générique ou le facteur relatif fixe du film choisi. `0.62` et `0.60D` sont les références de gamma et de densité grise du modèle générique. Ce ne sont pas des mesures de chaque film ou scanner. Les densités Status M ne caractérisent pas directement le RGB du scanner.

```math
D_c = \log_{10}(B_c / \max(T_c,10^{-5}))
```

```math
q_c = D_c/f_c,\quad k=0.045,\quad d_t=0.60+0.62\log_{10}(k/0.18),\quad p=d_t\ln(10)/0.62
```

```math
E_c=\begin{cases}
k\,\operatorname{sgn}(q_c)(|q_c|/d_t)^p,&q_c<d_t\\
0.18\times10^{(q_c-0.60)/0.62},&q_c\ge d_t
\end{cases}
```

Le pied en densité rejoint la partie droite avec la même valeur et la même pente. Le support non exposé donne une exposition de scène nulle avant la balance des blancs. Ce pied en puissance est un choix générique, pas une courbe mesurée par film. Près du support, le bruit de densité peut aussi être amplifié.

Les corrections automatiques restent optionnelles. Avec Couleur automatique, le support du film est exclu des échantillons de l’axe neutre avant le pied de sortie. Une forte dominante peut encore demander une balance des blancs manuelle.

## Courbe de sortie

La balance des blancs par canal et l’exposition agissent sur `E` linéaire. La même courbe fixe est appliquée à chaque canal après la balance des blancs. Sa partie médiane conserve les rapports RGB ; l’épaule modifie les rapports de couleur des hautes lumières. La plage `0.045...0.70` reste identique. Sous `0.045`, un faible plancher noir est ajouté : `b=0.001` en couleur et `0.0005` en noir et blanc. Au-dessus de `0.70`, l’épaule rationnelle tend vers 1. Les deux raccords ont une pente de 1. L’inversion du pied du film et le rendu du noir sont deux étapes distinctes.

```math
F(x)=x+b(1-x/0.045)^2\quad(0<x<0.045),\qquad F(x)=b\quad(x\le0)
```

Les niveaux automatiques ramènent leurs cibles par la courbe inverse avant l’étirement : noir de sortie `0.003`, blanc `0.95`. La couleur automatique exclut les échantillons ayant un canal linéaire inférieur ou égal à `0.004`. Le support non exposé vaut zéro et ne demande aucun seuil de bord distinct. Les cibles sans analyse de scène gardent des unités de référence fixes pour le gamma d’entrée. Pour les négatifs linéaires, la plage minimale vaut 4 % du blanc mesuré, plutôt qu’une exposition fixe de 0.04.

L’inversion n’a pas de plafond de `1.8D`. Le plancher de transmittance `1e-5` protège le logarithme. Le gamut est traité à la sortie. À cette étape, chaque canal reste entre le plancher noir et 1. Les réglages manuels suivants peuvent dépasser cette plage.

## Autres cibles

Les cibles scanner choisies explicitement conservent l’analyse de scène et `shoulder-print-response-v4`. La primitive fixe reste disponible. L’analyse n’utilise plus de plafond universel de 1.8D. Les préréglages de film utilisent des facteurs relatifs fixes sans normaliser chaque image.

Le RAW de film désactive les traitements de tonalité pris en charge par l’API. Sur macOS, scene-linear désactive les tons globaux et locaux, shadow bias et le gamut mapping. Windows utilise le transfert linéaire de LibRaw, séparément du rendu photo numérique. Ces réglages ne caractérisent pas le couple capteur-film et ne garantissent pas un RAW sans matrice couleur.

## Validation et sources

Les tests utilisent un modèle indépendant de la portion droite du film, une même plage sur plusieurs fonds, une gamme neutre pour la WB et des hautes lumières denses. Les régressions synthétiques ne prouvent pas la précision sur film réel. Les recettes existantes utilisent l’algorithme corrigé et conservent leurs paramètres et originaux. L’identifiant du moteur macOS et le suffixe des vignettes distinguent aussi le nouveau rendu.

Les équations ont été implémentées dans ce dépôt. Aucun code de darktable, RawTherapee ou NegPy n’a été copié.

## Comparaison synthétique mesurée

La régression reconstitue le chemin initial à partir du traitement v4 conservé, avec sa limite de plage à 1.8D et sa vibrance automatique. La même plage de densité `(0.48, 0.68, 0.70)` est comparée dans quatre fonds avec un support fixe. Ce n’est pas le test Reddit de 18 vues. Un modèle idéal distinct avec un pied lisse fournit les tests de tonalité et de balance des blancs, sans prouver la précision sur film réel.

| Mesure | Code initial | Première correction(v5) | Révision(v6) |
|---|---:|---:|---:|
| Étendue L* entre vues | 40.49 | 0 | 0 |
| Étendue b* entre vues | 35.22 | 0 | 0 |
| Contraste local à −3 EV | 1.57 | 2.17 | 0.97 |
| C* maximal de la gamme neutre après balance | 8.89 | 0.99 | <0.001 |

Les versions v5 et v6 utilisent le même modèle de pied direct. Un contraste local proche de 1 préserve environ un diaphragme de sortie pour un diaphragme d’entrée. L* et C* sont en Lab D50. La plage à support fixe reste teintée ; la cohérence ne rend pas neutre une densité arbitraire. Exécuter `FixedNegativeResponseTests` avec `NEGAFLOW_RESPONSE_COMPARISON` défini sur un chemin JSON conserve les mesures.

## Contrôle du rouleau fourni

Les 18 vues détectées dans `Roll_Perforation.tiff` ont aussi été comparées. Les deux méthodes utilisent la même estimation corrigée et fixe du support. L’étendue L* de la plage de même densité passe de 21.48 à <0.001 ; celle de b* passe de 30.94 à <0.001. La limite bleue initiale de 1.8D agit sur 18/18 vues. Ce contrôle suit l’idée du commentaire sans reproduire ses réglages exacts.

Il a révélé un autre défaut d’estimation du support. Un bord mêlant rétroéclairage et film remplaçait la mesure `(0.354, 0.109, 0.057)` par `(0.570, 0.510, 0.364)`. Les étapes de récupération et d’enveloppe refusent désormais une mesure ressemblant à la lumière sur les deux axes chromatiques du masque. La courbe de sortie agit aussi par canal après la balance des blancs : une valeur bleue extrême ne commande plus le rendu des autres canaux. Ce rouleau ne possède pas de référence colorimétrique mesurée. La cohérence et les limites de sortie ne prouvent pas la précision des couleurs. Définir `NEGAFLOW_RESPONSE_ROLL_DIR` sur un dossier et lancer `testBundledRollFrameConsistency` enregistre les images et le JSON.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
