# Comment la détection des vues sur scanner à plat trouve le film

[Accueil de la documentation](../README.md)

L'aperçu d'un scanner à plat montre un porte-film, la lumière qui passe à côté et le film chargé. Avant qu'une numérisation complète vaille la peine d'être lancée, la détection automatique des vues décide quelles parties sont du film et où une vue finit et la suivante commence. Elle connaît la taille réelle de la zone d'aperçu en millimètres : elle convertit donc un format de film en pixels de façon exacte.

## Le film se repère par sa texture

La luminosité ne distingue pas le film d'une fenêtre de porte-film vide. Mesures sur un aperçu Epson GT-X900 :

| Ce que contient la colonne | Luminosité moyenne |
|---|---|
| Fenêtre de porte-film vide, la lampe passe tout droit | 0.92 |
| Film dans la fenêtre voisine | 0.10 |
| Masque du porte-film | 0.002 |
| Porte-film tiers à fond blanc | 1.00 |

Un tri par luminosité choisit les fenêtres vides et écarte le film, et un fond de porte-film blanc inverse l'ordre. La texture les sépare, car le grain et une image n'existent que sur le film :

| Ce que contient la colonne | Détail vertical |
|---|---|
| Film | 0.0044 – 0.032 |
| Masque du porte-film, fenêtre vide, fond blanc | 0.00005 – 0.001 |

L'écart est d'un ordre de grandeur et garde son sens quels que soient le type de film, le porte-film et la polarité. Chaque étape ci-dessous s'appuie dessus.

## Étapes

1. Texture des colonnes. Le détail est mesuré le long de chaque colonne de l'aperçu. Les colonnes qui portent du grain et une image deviennent des candidats de fenêtre.
2. Fenêtres. Les colonnes candidates sont étendues jusqu'au bord du film et comparées à la largeur du format choisi. Une fenêtre qui touche le bord de la zone numérisée est écartée : la zone l'a coupée en deux et la numérisation complète capturerait la mauvaise région.
3. Bandes. Dans une fenêtre, les lignes qui portent du film sont séparées du porte-film au-dessus et au-dessous. Une ligne est du film si elle diffère du porte-film voisin ou porte de la texture. La luminosité seule perd les vues denses d'une diapositive, la texture seule perd les interstices et les vues plates.
4. Grille. Un peigne de positions d'interstices est ajusté sur le plan (pas, phase). Le score est le contraste entre l'intérieur d'une vue et l'intérieur de l'interstice, donc l'ajustement ne dépend pas de savoir si l'interstice est de la base claire, une densité maximale ou une nervure du porte-film.
5. Affinage. Chaque limite se cale sur l'interstice le plus proche, puis l'ensemble est réajusté à un espacement régulier, car les vues d'une bande sont régulièrement espacées. Numériser deux fois la même bande donne un écart de 0,2 mm au plus.

## Ce qu'elle refuse

| Situation | Résultat |
|---|---|
| Porte-film sans film | Rien. Les fenêtres n'ont pas de texture, aucune fenêtre ne se forme |
| Porte-film avec une seule bande dans trois fenêtres | Seulement la fenêtre chargée |
| Fenêtre coupée en deux par la zone de numérisation | Écartée |
| Une vue qui dépasse la fin du film | Écartée. Les vues intérieures sont gardées même non exposées |
| Une bande sans preuve d'interstices périodiques | Rien |

## Formats

La longueur le long de la bande est la direction du pas des vues et la longueur en travers est la largeur de la fenêtre. Les deux viennent du format choisi : demi-format et 645 ont donc leurs axes dans le bon sens.

| Format | Le long de la bande | En travers |
|---|---|---|
| 35 mm plein format | 36 mm | 24 mm |
| 35 mm carré | 24 mm | 24 mm |
| 35 mm demi-format | 18 mm | 24 mm |
| 120 · 6×4.5 | 41.5 mm | 56 mm |
| 120 · 6×6 – 6×17 | 56 – 168 mm | 55 – 56 mm |

Le pas du 35 mm est fixé par l'entraînement des perforations et bouge à peine : la recherche est étroite. Un appareil 120 fixe son propre espacement : la recherche est plus large. Aucun des deux n'est figé sur une valeur.

## Mesures

Dix vrais aperçus Epson GT-X900, 1768 × 2906 à 300 dpi sur une zone de 149,86 × 246,38 mm.

| Aperçu | Porte-film | Résultat |
|---|---|---|
| Négatif noir et blanc, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Négatif noir et blanc, une bande chargée | D'origine | 1 fenêtre × 6 vues, les deux fenêtres vides ignorées |
| Négatif couleur, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Négatif couleur, une bande chargée | D'origine | 1 fenêtre × 6 vues |
| Diapositive couleur, trois bandes | D'origine | 3 fenêtres × 6 vues |
| Diapositive couleur, une bande chargée | D'origine | 1 fenêtre × 6 vues |
| Négatif couleur, interstices masqués par le porte-film | Tiers | 1 fenêtre × 5 vues |
| Négatif couleur, porte-film plus large que la zone de numérisation | Tiers | 2 fenêtres entières, les deux demi-fenêtres écartées |

Pas ajusté sur toutes les bandes : 37,65 – 38,12 mm. La détection prend 0,5 – 0,9 s par aperçu dans un build de débogage.

> [!NOTE]
> Ces mesures ne concernent que le 35 mm. Les formats 120 sont couverts par des jeux synthétiques : la recherche d'espacement n'a pas encore été vérifiée sur un vrai aperçu 120.

## Où se trouve le code

| Fichier | Rôle |
|---|---|
| `FlatbedFrameGridDetector.swift` | Point d'entrée, géométrie des formats, étendue des vues |
| `FlatbedFrameGridDetector+Profiles.swift` | Profils de colonnes et de lignes, texture, statistiques communes |
| `FlatbedFrameGridDetector+Slots.swift` | Fenêtres, présence de film, bandes |
| `FlatbedFrameGridDetector+Grid.swift` | Indices d'interstices, ajustement du peigne, affinage des limites |

`FlatbedFrameDetector` reste le repli pour un aperçu dont la taille physique est inconnue.
