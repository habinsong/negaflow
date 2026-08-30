# De la photothèque à l’impression

[Accueil de la documentation](../README.md)

Ce guide décrit l’import, le développement par dossier, le transfert de réglages, les vignettes de scanner et la sortie d’impression. Un dossier de la photothèque correspond au dossier physique de la source ; ce n’est pas seulement une catégorie interne.

> [!IMPORTANT]
> Les sources restent intactes, sauf lorsque vous déplacez explicitement une photo vers un autre dossier. Retirer un dossier de la photothèque et supprimer un fichier dans le Finder sont deux opérations distinctes.

## Import

Sous les commandes d’import apparaissent une barre, un pourcentage, le nombre terminé et le total. Les métadonnées sont lues en arrière-plan, puis les nouvelles images sont enregistrées ensemble afin de ne pas réindexer la photothèque à répétition.

Le développement automatique des images importées est **désactivé par défaut**. La vignette de la source et le dossier apparaissent d’abord. Le développement commence lorsque vous appliquez un procédé et une cible au dossier, ou lorsque vous entrez dans Développement. Pour l’activer à chaque import, choisissez **Réglages → Flux de travail → Développer automatiquement les images importées**.

Le développement automatique ne concerne que les images ajoutées par cet import et ne remplace pas un état déjà développé. Une photo déjà développée n’est retraitée qu’après un **Appliquer** de dossier ou un collage de réglages demandé par l’utilisateur.

Les acquisitions scanner font exception : le film, le procédé et la cible ont déjà été choisis. Elles sont développées dès leur publication. Les bandeaux de Développement et Impression utilisent les vignettes développées pour les négatifs couleur, diapositives, négatifs noir et blanc et positifs noir et blanc.

## Dossiers

- L’état replié ou déplié est mémorisé. Créer un dossier ou relancer l’app ne déplie pas les autres.
- Le même `×` figure sur chaque ligne. Il retire le dossier de la **photothèque uniquement** et laisse les sources dans le Finder.
- Dans Développement, la liste des photos défile à l’intérieur du dossier sans repousser le reste de la barre latérale.

### Déplacer des photos vers un autre dossier

Glisser une photo ou une sélection vers un autre dossier déplace les fichiers physiques et met le catalogue à jour. La règle est la même pour les dossiers importés, créés par l’app ou issus d’un scanner. Si `frame.tiff` existe déjà, negaflow choisit `frame 2.tiff`, puis `frame 3.tiff`, sans écrasement. Le fichier IR associé est déplacé dans la même transaction.

### Changements dans le Finder

Après un déplacement ou un renommage dans le Finder, le signet persistant reconnecte la photo ou le dossier existant. Une nouvelle image placée directement dans un dossier enregistré est aussi importée. Seul le dossier ayant signalé un changement est relu ; il n’y a pas de balayage périodique de toute la photothèque.

## Développement par dossier

Choisissez le procédé et la cible à côté du nom du dossier, puis **Appliquer**. Il n’y a pas d’interrupteur supplémentaire.

Toutes les photos du dossier sont recalculées, y compris celles déjà développées. Le nouveau procédé et la nouvelle cible sont utilisés, tandis que les autres corrections manuelles, comme l’exposition et le contraste, sont conservées. Une barre, un pourcentage, le nombre terminé et le total s’affichent à côté d’Appliquer. La file n’utilise que le nombre de tâches correspondant aux emplacements de rendu disponibles.

## Préréglages et copier-coller

| Groupe | Valeurs |
|---|---|
| Base | Type et procédé du film, cible, profil scanner, base du film |
| Tonalité | Exposition, contraste, densité, hautes lumières, ombres, blancs, noirs et courbes |
| Couleur | Température, teinte, saturation, mélangeur, étalonnage, virage N&B et émulation |
| Détails | Grain, netteté, halo, clarté, vignette, réduction du bruit, GrainMend et corrections locales |
| Géométrie | Recadrage, rotation, retournements, redressement et format de recadrage |

Un collage complet utilise les cinq groupes. Un collage partiel ne change que les groupes choisis. Avec plusieurs photos sélectionnées, il s’applique à toute la sélection. Les préréglages utilisateur conservent le même état de développement complet, géométrie comprise.

## Sans module scanner

Si aucun module n’est installé au démarrage, la barre latérale commune de Photothèque et Développement n’affiche pas automatiquement l’explication d’absence, la recherche à nouveau et le simulateur. L’import d’images reste disponible. La recherche et le simulateur ne sont pas supprimés : on peut encore les ouvrir depuis l’entrée Scanner ou les Réglages.

## Mises en page et nombre de sorties

Impression propose sept mises en page : image unique, planche-contact, package d’images, package personnalisé, cyanotype, plaque de verre et gélatino-argentique. Les trois dernières réutilisent l’inspecteur de l’image unique. Avec plusieurs photos, les quatre dispositions individuelles présentent une page terminée par photo dans un défilement vertical.

L’export du tirage et l’exportation rapide comptent les pages finies, pas les sources sélectionnées. Ainsi, 39 photos sur une planche 6 × 7 donnent un fichier composé ; un package de quatre images donne 10 pages ; le package personnalisé par défaut donne une page ; les dispositions individuelles donnent un lot borné de 39 fichiers.

L’aperçu réutilise toute vignette, image développée ou prévisualisation source disponible et ne crée une petite prévisualisation rapide qu’en leur absence. L’export final calcule les placements depuis les métadonnées, ne développe que les pixels nécessaires, prépare deux à quatre sources à la fois et conserve le graphe Core Image jusqu’au rendu final. Un contexte partagé et une limite de 512 Mio de rastérisation source par page évitent les intermédiaires pleine résolution non bornés.

## Profils d’impression

| Réglage | Aperçu | Export d’impression | Développement |
|---|---|---|---|
| Profil de sortie imprimante | Montre le résultat | Appliqué à la page composée | Jamais appliqué |
| Profil d’épreuve C-print | Simule le laboratoire et le papier | Non incorporé au fichier livré | Jamais appliqué |

Le profil de sortie est appliqué une fois, après la composition complète de la planche-contact, du paquet photo ou du paquet personnalisé. Les placements répétés et les mises en page à plusieurs photos reçoivent tous la même conversion. Voir [Mises en page et aperçu C-print](../reference/C_PRINT.md).

## Ce qui touche aux originaux

| Action | Original dans le Finder | Catalogue et retouches |
|---|---|---|
| `×` sur un dossier | Intact | Le dossier et ses photos quittent la bibliothèque |
| Glisser une photo vers un autre dossier | Déplacé ; nouveau nom en cas de collision | Relié au nouvel emplacement |
| Déplacement ou renommage dans le Finder | Le changement de l'utilisateur est conservé | Relié automatiquement par le signet |
| Développement appliqué au dossier | Intact | Processus et cible mis à jour, puis rendu à nouveau |
| Préréglage ou copier-coller | Intact | Valeurs de développement et de géométrie mises à jour |
| Export d'impression | Intact | Un fichier de sortie et un relevé de rendu sont créés |

## Vérification de 2 000 images

Au-delà de 256 photos, le bandeau évite les longs déplacements automatiques et ne crée que les éléments nécessaires. Le test de 2 000 images répartit des sources 24 MP, 40 MP, 60 MP, 3200 DPI et 4800 DPI dans 50 dossiers, mélange tous les procédés et cibles, le recadrage et l’orientation, puis contrôle le développement, les vignettes et le catalogue.

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

Ce test long est ignoré par un `swift test` normal.
