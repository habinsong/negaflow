# Comment la détection des vues sur scanner à plat trouve le film

[Accueil de la documentation](../README.md)

Un aperçu de scanner à plat montre un porte-films, la lumière qui passe à côté, et le film chargé, s'il y en a. La détection automatique doit décider quelles parties de cette image sont du film, et où une vue se termine et où la suivante commence, avant que le scan définitif ne vaille la peine.

Le détecteur connaît la taille réelle de la zone prévisualisée en millimètres : il convertit donc un format de film en pixels exactement, au lieu de le deviner à partir de proportions.

## Le film se reconnaît à son grain, pas à sa luminosité

La luminosité ne distingue pas le film d'une fenêtre vide du porte-films. Mesures sur un aperçu Epson GT-X900 :

| Contenu de la colonne | Luminosité moyenne |
|---|---|
| Fenêtre vide, la lampe passe directement | 0,92 |
| Film dans la fenêtre voisine | 0,10 |
| Masque du porte-films | 0,002 |
| Porte-films tiers à fond blanc | 1,00 |

Trier par luminosité revient donc à retenir les fenêtres vides et à écarter le film ; un porte-films à fond blanc inverse purement et simplement l'ordre.

Le grain lève cette ambiguïté, parce que grain et image n'existent que sur le film :

| Contenu de la colonne | Détail vertical |
|---|---|
| Film | 0,0044 à 0,032 |
| Masque, fenêtre vide, fond blanc | 0,00005 à 0,001 |

L'écart dépasse un ordre de grandeur et ne change pas de sens selon le type de film, le porte-films ou la polarité. Toutes les étapes ci-dessous reposent dessus.

## Étapes

1. **Grain par colonne.** Le détail est mesuré le long de chaque colonne de l'aperçu. Les colonnes qui portent du grain et une image deviennent des candidates.
2. **Fenêtres.** Les colonnes candidates sont étendues jusqu'au bord du film puis comparées à la largeur du format choisi. Une fenêtre qui touche le bord de la zone numérisée est écartée : la zone de scan l'a coupée en deux et le scan définitif capturerait la mauvaise région.
3. **Bandes.** Dans une fenêtre, les lignes qui portent du film sont séparées du porte-films au-dessus et au-dessous. Une ligne compte comme film si elle diffère du porte-films voisin **ou** si elle porte du grain ; la luminosité seule perd les vues denses d'une diapositive, le grain seul perd les interstices et les vues plates.
4. **Grille.** Un peigne de positions d'interstice est ajusté sur tout le plan (pas, phase). Le score est le contraste entre l'intérieur d'une vue et l'interstice : l'ajustement ne dépend donc pas de ce que l'interstice soit du support transparent, une densité maximale, ou une barrette du porte-films qui le recouvre.
5. **Affinage.** Chaque limite est calée sur l'interstice le plus proche, puis l'ensemble est réajusté à un espacement régulier, car les vues d'une bande sont régulièrement espacées. Deux numérisations de la même bande tombent à 0,2 mm près.

## Ce qu'il refuse

| Situation | Résultat |
|---|---|
| Porte-films sans film | Rien. Les fenêtres n'ont pas de grain, aucune fenêtre ne se forme |
| Une seule bande dans trois fenêtres | Uniquement la fenêtre chargée |
| Fenêtre coupée en deux par la zone de scan | Écartée |
| Vue qui dépasse l'extrémité du film | Écartée ; les vues intérieures sont gardées même vierges |
| Bande sans preuve d'interstices périodiques | Rien, plutôt qu'une grille arbitraire |

## Formats

La longueur le long de la bande est la direction du pas, la longueur en travers est la largeur de la fenêtre. Les deux viennent du format choisi : le demi-format et le 645 ont donc leurs deux axes dans le bon sens.

| Format | Le long de la bande | En travers |
|---|---|---|
| 35 mm plein format | 36 mm | 24 mm |
| 35 mm carré | 24 mm | 24 mm |
| 35 mm demi-format | 18 mm | 24 mm |
| 120 · 6×4,5 | 41,5 mm | 56 mm |
| 120 · 6×6 à 6×17 | 56 à 168 mm | 55 à 56 mm |

Le pas du 35 mm est fixé par l'entraînement à perforations et bouge à peine : la recherche est donc étroite. Un appareil 120 fixe lui-même son espacement, la recherche est plus large. Ni l'un ni l'autre n'est figé sur une valeur.

## Mesures effectuées

Dix aperçus réels d'un Epson GT-X900, 1768 × 2906 à 300 ppp sur une zone de 149,86 × 246,38 mm.

| Aperçu | Porte-films | Résultat |
|---|---|---|
| Négatif noir et blanc, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Négatif noir et blanc, une seule bande | D'origine | 1 fenêtre × 6 vues, les deux vides ignorées |
| Négatif couleur, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Négatif couleur, une seule bande | D'origine | 1 fenêtre × 6 vues |
| Diapositive couleur, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Diapositive couleur, une seule bande | D'origine | 1 fenêtre × 6 vues |
| Négatif couleur, interstices masqués | Tiers | 1 fenêtre × 5 vues |
| Négatif couleur, porte-films plus large que la zone | Tiers | 2 fenêtres entières ; les 2 moitiés écartées |

Pas ajusté sur toutes les bandes : 37,65 à 38,12 mm. La détection prend 0,5 à 0,9 s par aperçu en compilation de débogage.

> [!NOTE]
> Ces mesures ne couvrent que le 35 mm. Les formats 120 ne reposent que sur des images de synthèse ; leur recherche d'espacement n'a pas encore été vérifiée sur un aperçu 120 réel.

## Où se trouve le code

| Fichier | Rôle |
|---|---|
| `FlatbedFrameGridDetector.swift` | Point d'entrée, géométrie du format, étendue des vues |
| `FlatbedFrameGridDetector+Profiles.swift` | Profils de colonnes et de lignes, grain, statistiques communes |
| `FlatbedFrameGridDetector+Slots.swift` | Fenêtres, présence du film, bandes |
| `FlatbedFrameGridDetector+Grid.swift` | Indices d'interstice, ajustement du peigne, affinage des limites |

`FlatbedFrameDetector` reste le recours pour un aperçu dont la taille physique est inconnue.
