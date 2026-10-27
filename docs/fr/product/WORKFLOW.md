# De la photothèque à l’impression

[Accueil de la documentation](../README.md)

Ce guide décrit l’import, le développement par dossier, le transfert de réglages, les vignettes de scanner et la sortie d’impression. Un dossier de la photothèque correspond au dossier physique de la source.

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

Les réglages se répartissent en sept groupes indépendants.

| Groupe | Valeurs |
|---|---|
| Gamma d’entrée | Interprétation de la courbe de transfert source |
| Échelle de base | Multiplicateur de la base du film |
| Base | Type et procédé du film, cible, profil scanner, base, correction des plages par canal, balance automatique, niveaux et balance neutre |
| Tonalité | Exposition, contraste, densité, hautes lumières, ombres, blancs, noirs et courbes |
| Couleur | Température, teinte, profondeur de couleur, vibrance, saturation, mélangeur, étalonnage, calibration, virage N&B et émulation |
| Détails | Grain, netteté, halo, clarté, vignette, réduction du bruit, intensité GrainMend et corrections locales |
| Géométrie | Recadrage, rotation, retournements, redressement et format de recadrage |

Un collage complet ou un préréglage utilisateur remplace les réglages de développement de la destination. Un collage partiel remplace les valeurs effectives des groupes choisis et conserve les autres. Lorsqu’une partie du look est collée, ses contributions au ton, à la couleur et à la texture sont intégrées aux valeurs, puis sa référence est retirée. L’ancien look ne s’ajoute donc pas une seconde fois. Répéter le collage conserve le même état. Le panneau, les menus et les raccourcis utilisent la même portée.

Le collage et les préréglages s’appliquent à toutes les photos sélectionnées. Une seule annulation ou restauration couvre la sélection entière. Windows valide toutes les destinations avant de les modifier. Les vignettes et l’aperçu actif sont mis à jour avec les nouveaux réglages. Les originaux, les notes et les retouches de défauts liées à la source ne sont pas copiés.

Les préréglages utilisateur conservent le développement complet et la géométrie. Les anciens formats sans champ Géométrie l’incluent par compatibilité. Un nom vide reçoit le premier numéro libre. Un nom identique ne provoque pas l’écrasement d’un préréglage existant.

## Sans module scanner

Si aucun module n’est installé au démarrage, la barre latérale commune de Photothèque et Développement n’affiche pas automatiquement l’explication d’absence, la recherche à nouveau et le simulateur. L’import d’images reste disponible. La recherche et le simulateur ne sont pas supprimés : on peut encore les ouvrir depuis l’entrée Scanner ou les Réglages.

## Mises en page et nombre de sorties

Impression propose huit mises en page : image unique, planche-contact, package d’images, package personnalisé, cyanotype, plaque de verre, gélatino-argentique et filigrane. Les cinq dispositions individuelles créent une page par photo sélectionnée et les présentent verticalement. Filigrane est une mise en page distincte ; les autres commandes restent inchangées.

L’export du tirage et l’exportation rapide comptent les pages finies. Ainsi, 39 photos sur une planche 6 × 7 donnent un fichier composé ; un package de quatre images donne 10 pages ; le package personnalisé par défaut donne une page ; les dispositions individuelles donnent un lot borné de 39 fichiers.

L’aperçu réutilise toute vignette, image développée ou prévisualisation source disponible et ne crée une petite prévisualisation rapide qu’en leur absence. L’export final calcule les placements depuis les métadonnées, ne développe que les pixels nécessaires, prépare deux à quatre sources à la fois et conserve le graphe Core Image jusqu’au rendu final. Un contexte partagé et une limite de 512 Mio de rastérisation source par page évitent les intermédiaires pleine résolution non bornés.

## Filigrane d’impression

Choisissez Filigrane après Gélatino-argentique dans le type de mise en page. Une bordure est ajoutée sous la photo sans recadrage ; une bordure de même hauteur peut être ajoutée au-dessus. Le format Photo tient compte des bordures.

La bordure du bas affiche à gauche l’appareil, avec l’objectif en dessous. À droite viennent un logo, puis la focale, l’ouverture, la vitesse et l’ISO, avec la date en dessous. Activez Logo pour en ajouter un. Sans fichier choisi, le logo negaflow est utilisé. negaflow ne fournit aucun logo de marque : choisissez votre propre fichier JPEG, PNG ou autre image. Les réglages et les modèles gardent seulement le chemin du fichier. Le rendu vérifie le fichier et réemploie le logo en cache tant que sa taille et sa date de modification restent les mêmes. Si le fichier a été déplacé ou supprimé, seul le logo est omis ; le point d’état en bas et le rapport de diagnostic le consignent. Les champs appareil, objectif, exposition et date laissés vides restent vides. Seul le texte saisi est dessiné. Si le texte est long ou si la bordure est étroite, comme sur une photo verticale, tous les éléments de la bordure sont réduits dans la même proportion. Le texte ne déborde pas de la photo et n’est pas coupé.

La bordure peut être blanche, noire ou un flou de la photo. Sur blanc, le texte est noir et les secondes lignes sont grises. Sur noir, tout le texte est blanc. Sur flou, vous choisissez noir ou blanc pour le texte et pour l’histogramme. L’histogramme est dessiné en colonnes de points. L’histogramme et votre nom se placent chacun en bas au centre, ou en haut à gauche, au centre ou à droite quand la bordure du haut est active. Le menu de position du nom reste visible : en bas au centre, en haut à gauche, au centre ou à droite. Choisir une position haute active la bordure haute. Le nom est centré dans son emplacement. Si le nom et l’histogramme partagent un emplacement, l’histogramme se place au-dessus du nom et chacun est centré. Le flou et l’histogramme réemploient une vignette valide de la bande de film quand elle est disponible. Sinon, ils utilisent une image réduite de la photo. Les modèles enregistrent la couleur du papier et tous les réglages du filigrane, textes et chemin du logo compris.

## Profils d’impression

| Réglage | Aperçu | Export d’impression | Développement |
|---|---|---|---|
| Profil de sortie imprimante | Montre le résultat | Appliqué à la page composée | Jamais appliqué |
| Profil d’épreuve C-print | Simule le laboratoire et le papier | Non incorporé au fichier livré | Jamais appliqué |

Le profil de sortie est appliqué une fois, après la composition complète de la planche-contact, du paquet photo ou du paquet personnalisé. Les placements répétés et les mises en page à plusieurs photos reçoivent tous la même conversion. Voir [Mises en page et aperçu C-print](../reference/C_PRINT.md).

## Export DNG

Le DNG écrit la photo développée en RGB linéaire 16 bits (`PhotometricInterpretation = LinearRaw`), sans compression, dans l’espace colorimétrique choisi à l’export : sRGB, Display P3 ou Adobe RGB. Le ton et la couleur sont déjà appliqués, donc les autres applications lisent un fichier référencé sortie. Le fichier porte le droit d’auteur, le scanner, le logiciel, la date et les notes de film selon la même politique de métadonnées que le TIFF. L’EXIF, l’IPTC et le GPS de l’appareil source ne sont pas copiés. Il faut 6 octets par pixel : une photo de 24 mégapixels pèse environ 144 Mo.

Le DNG est proposé pour les sources non compressées : TIFF, RAW d’appareil et DNG. Les sources JPEG, PNG et HEIC ne s’exportent pas en DNG. Le développement, la cible `PRINT` et les mises en page d’impression prennent en charge le DNG. Le DNG d’impression enregistre la page composée en RGB standard avec une ColorMatrix, sans conversion ICC d’imprimante. L’export DNG utilise le dossier sélectionné dans Export et l’extension `.dng`. La fin de l’export exige la publication et la vérification du fichier final. exiftool et le décodeur d’images d’Apple lisent le fichier. Le rendu dans Lightroom ou Camera Raw n’a pas été mesuré.

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
