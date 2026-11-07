# GrainMend

[Accueil de la documentation](../README.md)

GrainMend répare les poussières, micro-trous, rayures et dégâts d'émulsion du film. Rien n'est incrusté dans l'original ; le résultat est conservé sous forme d'historique de retouches ordonné.

| Outil | Ce qu'il regarde | Comment il répare |
|---|---|---|
| Automatique | Toute la photographie | Prudent, seulement les défauts dont il est sûr |
| Guidé | Une zone que vous choisissez | Examine de près, jusqu'aux petits points et aux défauts discrets |
| Pinceau | L'endroit que vous peignez | Reporte la structure et la texture environnantes |
| Tampon de clonage | Un point source que vous choisissez | Copie de vrais pixels sources à un décalage fixe |
| IR | Le canal infrarouge du scanner | L'IR trouve l'emplacement, le RVB reconstruit les pixels |

L'écran de développement propose automatique, guidé, pinceau et tampon de clonage. L'IR peut être activé à l'étape de numérisation quand le module signale la capacité, et une fois la numérisation faite, son résultat rejoint la même liste de calques GrainMend.

> [!CAUTION]
> GrainMend RGB fonctionne autrement que le nettoyage IR matériel. GrainMend IR n'est ni une implémentation ni un mode de compatibilité de Digital ICE, iSRD ou SRDx.

## Ce qui est difficile

Les défauts du film et la structure de la photographie occupent les mêmes pixels.

- La poussière apparaît comme de petites taches irrégulières, claires ou sombres.
- Un micro-trou peut ressembler à un point isolé et vif.
- Les rayures sont longues et fines, comme les fils, les cadres de fenêtre et les inscriptions.
- Les dégâts d'émulsion changent à la fois la couleur et la texture.
- À haute résolution, le grain du film a la taille d'un petit défaut.

Effacer les hautes fréquences en bloc emporte le grain et les contours avec la poussière. GrainMend divise le travail en détection, classification, réparation et stockage.

## Ordre du travail

Le masque de détection et le résultat réparé sont conservés séparément, ce qui permet d'examiner le masque, de n'appliquer qu'une partie des défauts ou de reconstruire la réparation. Les étapes :

1. Image d'entrée, zone d'inspection et taille.
2. Candidats de défauts, puis nettoyage du masque.
3. Classification des défauts.
4. Contrôle de structure : si c'est une structure de la photo, rien n'est appliqué.
5. Recherche d'une pièce source à proximité.
6. Accord de la luminosité, de la texture et de la direction.
7. Fondu de la limite.
8. Ajout à l'historique des retouches.

## Outils

### Automatique

Sur toute la photographie, il ne trouve que les défauts dont il est sûr. Il vaut mieux manquer un petit défaut que d'effacer à tort une grande structure. Il ne se glisse jamais dans le développement par défaut : il faut le lancer pour qu'il ajoute quoi que ce soit.

### Guidé

Vous choisissez un rectangle, et seuls cette zone et ses abords sont analysés. Comme vous avez déjà désigné le défaut, il poursuit plus vivement que l'automatique les petits points, les défauts discrets et les amas denses.

Il lit plus large que le résultat qu'il produit : les pixels environnants servant à la réparation ne sont pas coupés au bord de la zone. Le rayon de contexte maximal actuel est de 264 pixels.

### Pinceau

Vous peignez vous-même l'endroit à réparer. Il ne recouvre pas ce que vous avez peint d'une couleur : il trouve une pièce source correspondante près du masque et reporte la structure et la texture. Faute de pièce adéquate, il peut se rabattre de façon limitée sur le chemin de détection.

### Tampon de clonage

Un clic avec `⌥` choisit le point source, puis vous dessinez sur la cible. Il n'utilise aucune détection automatique : il garde le décalage entre les deux points et copie les vrais pixels.

L'historique des retouches conserve le diamètre, la dureté, les coordonnées et le décalage, et s'applique toujours aux mêmes coordonnées d'origine après une rotation, un retournement ou un recadrage. Les décalages sont arrondis au pixel entier, et rien en dehors de l'image n'est appliqué.

### IR

N'est utilisé que lorsque le module fournit un vrai canal IR dont la taille et la zone correspondent au RVB. L'IR est la matière qui localise le défaut. Les pixels finaux viennent du même réparateur que pour le RVB.

## Trouver les défauts en RVB

### Différence avec l'environnement

La luminosité varie d'une photographie à l'autre, il n'y a donc pas de seuil global unique. La différence avec la luminosité environnante, la variance locale et la direction produisent des candidats de poussière claire et de défauts sombres.

### Nettoyage du masque

Le bruit isolé est écarté, les défauts coupés sont reliés, et les pixels qui se touchent dans l'une des 8 directions forment une seule tache. Une grande zone peut être découpée en tuiles, mais une tache à cheval sur une limite est refusionnée dans les coordonnées de l'image entière.

### Différences de résolution

Un même grain de poussière occupe un nombre de pixels différent à 1200 dpi et à 7200 dpi. Quand l'information de résolution est fiable, les limites suivent la taille réelle. Sans elle, le modèle de scanner n'est pas deviné et une règle prudente en pixels s'applique.

### Classification

Chaque tache est mesurée selon :

- La surface et le cadre englobant
- Le rapport du grand axe au petit axe
- La direction horizontale, verticale ou diagonale
- La linéarité, la densité et le contraste environnant
- Le fait qu'elle se prolonge dans un contour proche
- Sa relation avec les autres taches

Le résultat est réparti en poussière, micro-trou, rayures par direction, dégâts d'émulsion et micro-points, chacun avec une confiance.

### Ne pas effacer les lignes qui font partie de la photo

Les fils, rambardes, angles de bâtiments, cadres de fenêtre et inscriptions ne doivent pas être pris pour des rayures. Les lignes parallèles, les grilles, la continuité des contours et les lignes attachées à la structure de la scène font l'objet d'un contrôle propre. L'automatique rejette les faux positifs plus strictement ; le guidé tient aussi compte de votre choix d'emplacement.

## Réparation

1. Trouver près du défaut une pièce source qui ne recouvre pas le masque et dont la structure correspond.
2. Accorder la luminosité et la différence de couleur de basse fréquence entre la pièce et la cible.
3. Garder la texture haute fréquence de la pièce pour que le grain du film se prolonge.
4. Pour une longue rayure, regarder d'abord la direction qui se prolonge depuis les deux extrémités.
5. Au bord du masque, fondre en douceur l'original et la pièce réparée.

L'intensité est le rapport de mélange entre la pièce terminée et l'original.

Il arrive qu'une réparation automatique ne puisse pas savoir ce qu'il y avait dessous. S'il n'y a pas de texture environnante utilisable, ou si le défaut couvrait toute une structure importante, il faut le pinceau, le tampon de clonage ou un travail précis à part.

## Traitement de l'IR

### Conditions d'entrée

- Le module signale explicitement la capacité IR.
- Le RVB et l'IR appartiennent à la même session de numérisation.
- Les deux images ont la même taille en pixels et la même zone attendue.
- Les fichiers sont lisibles et passent le contrôle d'identifiant d'origine.

Même si l'on sait qu'un modèle a de l'IR, il n'est pas utilisé à l'écran ni dans une requête tant que le module ne le signale pas.

### Alignement

L'optique et la lecture du capteur peuvent laisser le RVB et l'IR décalés de quelques pixels. Une recherche large, puis une recherche étroite, fixent le décalage. La confiance du pic et le fait qu'il tombe au bord de la plage de recherche sont tous deux consignés.

Une confiance faible, ou un meilleur point coincé au bout de la recherche, ne compte pas comme un succès.

### Soustraction du motif de scène

Les colorants et la densité du film peuvent transparaître dans l'IR. La luminosité logarithmique du canal rouge est découpée en 64 intervalles, et dans chacun on prend la moyenne après avoir écarté les 10 % les plus hauts et les plus bas des valeurs IR. Les intervalles vides sont interpolés à partir de leurs voisins et lissés par un court noyau symétrique. Soustraire cette courbe non paramétrique réduit le motif de scène, et la poussière sombre et clairsemée reste hors des statistiques des intervalles.

Le reste est converti en contraste relatif à la moyenne locale. Pour qu'un grand défaut ne relève pas le plancher de bruit environnant, l'entrée de bruit est écrêtée au contraste de détection minimal avant le calcul du seuil adaptatif. Les zones sombres connexes au niveau du porte-film et du bord du film sont retirées du masque.

### Conditions de sécurité

- Un masque anormalement large n'est pas appliqué.
- Un alignement qui n'a pas pu être confirmé n'est pas appliqué.
- Il n'est pas appliqué automatiquement au noir et blanc argentique.
- Les positifs couleur et les émulsions spéciales ne sont pas supposés sûrs sans mesure.

Les outils IR du commerce imposent aussi leurs propres limites au noir et blanc ordinaire et à Kodachrome :

- [SilverFast: iSRD dust and scratch removal](https://www.silverfast.com/about-silverfast-why-scanning-basics-of-scanning/why-silverfast/silverfast-feature-highlights/isrd-dust-scratches-removal-eliminate-defects-with-infrared-channel/)

GrainMend IR n'est ni une copie ni un mode de compatibilité de ces outils du commerce. Les limites de l'IR par film et les conditions d'échec de l'alignement sont dans [Films que GrainMend IR doit éviter](../reference/INFRARED_LIMITS.md).

## Historique des retouches et stockage

Automatique, guidé, pinceau, tampon de clonage et IR partagent une même liste de retouches ordonnée.

Ce que porte chaque entrée :

- Identifiant et type
- Ordre d'application
- Activée ou non, et son intensité
- Zone, masque, décalage de la source de clonage
- Classification du défaut et valeurs de diagnostic
- Vue d'origine et version de la retouche
- La pièce réparée, ou les valeurs nécessaires pour la reconstruire

Une réparation antérieure change l'entrée de la suivante : l'ordre de la liste fait donc aussi partie de l'historique.

L'original n'est pas modifié. L'historique GrainMend est stocké dans un fichier annexe géré par l'application. Le SHA-256 de l'original, la version de la retouche et l'empreinte de l'historique lient l'entrée. Si le fichier annexe est absent ou abîmé, le cache n'est pas traité comme un original.

Le cache GrainMend est un fichier dérivé, destiné à l'affichage rapide et au nouveau rendu. S'il est absent ou échoue à son contrôle, il est reconstruit à partir de l'original et de l'historique. Si le résultat dont un export a besoin ne peut pas être produit, l'export échoue au lieu de lui substituer l'original.

## Performances

- Une petite retouche ne recalcule que le défaut et son contexte environnant.
- Une grande zone est découpée en tuiles qui se recouvrent, avec une marge pour la limite.
- Les résultats ne sont recueillis que dans les centres non recouvrants des tuiles.
- Quatre tuiles au plus sont traitées à la fois.
- `CleanedRawCanvas` ne copie que le rectangle qui a changé.
- Les copies pour l'annulation partagent le stockage tant que rien n'a vraiment changé.
- Sous pression mémoire, les images reconstructibles et le cache des pièces sont abandonnés.

Les durées réelles dépendent de la résolution, du nombre de défauts, de la taille de la zone et du Mac.

Mesuré le 2026-07-25 sur un build Release, Mac14,3, arm64, 24 Gio de mémoire, macOS 26.5 :

| Chemin | Entrée | Résultat |
|---|---|---:|
| Détection guidée | 1600×1600, 25 grains de poussière | 0,35 s, 25 détectés |
| Détection ROI partielle | 1600×1600 | 0,38 s |
| Charge guidée dense | 1280×960, 8 images × 3 passages | médiane 0,423 s, p95 0,488 s, max 0,526 s |
| Détection IR | 6000×4000, 24 MP | 1,042 s, pic de croissance mémoire 249,2 Mio |

Sur 24 passages de charge dense, la couverture de masque la plus basse aux emplacements des défauts était de 99,80 % et l'erreur résiduelle moyenne la plus haute de 2,70/255. Ce sont des mesures de régression sur une entrée synthétique. Elles ne promettent aucune durée sur un autre Mac ni sur un vrai film.

## Banc d'essai

`defect-bench` peut produire ces fichiers et valeurs :

- Avant, après, différence, masque
- Recadrages à 100 %
- Nombre de détections et confiance
- Temps de traitement
- PSNR et erreur absolue quand des images de référence existent

```bash
swift run -c release negaflow defect-bench <input-dir> \
  --reference-dir <reference-dir> \
  --out <report-dir>
```

La régression RVB utilise les 44 paires abîmé/restauré par un expert de FILM-R v2 :

- Jeu de données : Authentically damaged & manually restored film scans (FILM-R v2)
- Auteur : Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- Licence: CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>)
- Paires: 44
- Taille totale: 437,570,872 bytes

Le chemin automatique applique une sensibilité de 0,7 et une ligne de sécurité contre la sur-détection. Sur les 44 paires de FILM-R, 34 images se sont améliorées et 6 se sont dégradées. La variation moyenne de PSNR est de +0,466 dB, le pire cas de −1,338 dB, et les pixels dégradés pondérés représentent 0,017 %.

Quand l'automatique rencontre une forte densité de candidats, il cesse d'appliquer et vous oriente vers le guidé. Cette ligne de sécurité ne s'applique pas au guidé, où vous fixez la zone, ni au pinceau, au tampon de clonage ou à l'IR. 6 images ont encore un PSNR inférieur à la restauration d'expert. Rien de tout cela ne prouve que toute photographie s'améliore, que RVB et IR sont équivalents, ni quoi que ce soit sur la qualité de l'IR sur un vrai scanner.

## Couverture des tests

- Connexité à 8 directions et masques
- Opérations morphologiques
- Détection de poussières, de rayures et de micro-points
- Rejet des lignes et des grilles comme faux positifs
- Limites de tuiles dans une grande zone
- Réparation de rayures par direction
- Accord de la texture et de la luminosité environnantes
- Masques du pinceau
- Décalage, dureté et composition de pièces du tampon de clonage
- Alignement IR, ancrages, taches et limites mémoire
- Application à l'étape de l'original et rendu de l'historique des retouches de l'application
- Ajouts répétés et annulation
- Propriété des vues pendant la navigation dans l'écran

Certains tests de performance ne tournent que si une variable d'environnement est définie. La présence d'un fichier de test n'affirme pas qu'il a tourné dans tous les environnements.

## Noms et marques

`GrainMend` est le nom de fonction propre à negaflow.

- `Digital ICE` peut être une marque d'Eastman Kodak Company ou d'un titulaire de droits associé.
- `iSRD`, `SRDx` et `SilverFast` sont des marques de LaserSoft Imaging.
- Ces noms ne servent qu'à la comparaison technique et à l'identification de produits.
- GrainMend ne revendique aucune affiliation, compatibilité ni équivalence avec une technologie tierce.

## Où se trouve le code

- `Sources/Chromabase/DefectRemoval/`
- `Sources/negaflowApp/Features/Defects/`
- `Sources/negaflowApp/Features/Develop/Inspector/Tools/DefectControlsSection.swift`
- `Sources/negaflowCLI/Commands/CLI+DefectBenchCommand.swift`
- `Tests/ChromabaseTests/Defect*.swift`
- `Tests/negaflowAppTests/Defect*.swift`
- `Config/defect-corpus-film-r-v2.json`
- `scripts/defect-corpus/`
