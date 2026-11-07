# De la bibliothèque au tirage

[Accueil de la documentation](../README.md)

Ce guide couvre l'import, le développement par dossier, le transfert de réglages, les vignettes de scanner et la sortie de tirage. Un dossier de la bibliothèque suit le dossier parent physique de chaque source.

> [!IMPORTANT]
> Les fichiers sources restent inchangés tant que vous ne déplacez pas explicitement une photo vers un autre dossier. Retirer un dossier de la bibliothèque et supprimer un fichier dans le Finder sont deux actions distinctes.

## Import

L'import affiche une barre de progression, un pourcentage, le nombre de fichiers terminés et le total sous les commandes d'import. Les métadonnées sont lues hors du fil principal, puis les nouvelles vues sont enregistrées ensemble : un gros dossier ne reconstruit pas l'index de la bibliothèque à répétition.

Le développement automatique des photos importées est **désactivé par défaut**. Un import se déroule ainsi :

1. La source est enregistrée.
2. Sa vignette d'origine et son dossier apparaissent d'abord.
3. Le développement démarre quand vous appliquez un procédé et une cible au dossier ou que vous entrez dans la vue Développement.

Pour développer automatiquement chaque import, activez **Réglages → Flux de travail → Développer automatiquement les nouvelles importations**. Ce choix persiste d'un lancement à l'autre. Il ne concerne que les vues enregistrées par cet import et ne remplace jamais un état déjà développé. Les photos développées ne sont retraitées que par un **Appliquer** explicite sur le dossier ou par un collage de réglages.

Les captures de scanner sont différentes : type de film, procédé et cible sont choisis pendant la numérisation, donc le développement démarre une fois le résultat publié. Les pellicules des vues Développement et Tirage affichent une vignette développée pour les sources négatif couleur, diapositive, négatif noir et blanc et positif noir et blanc. La Bibliothèque garde la vignette source pour contrôler la source.

## Liste des dossiers

- Les états replié et déplié persistent. Créer un dossier ou rouvrir l'application ne déplie pas les autres dossiers.
- Chaque ligne de dossier a la même commande `×`. Elle retire ce dossier et ses photos **de la bibliothèque seulement**. Les fichiers sources restent dans le Finder.
- La liste des photos d'un dossier dans Développement a sa propre zone de défilement à hauteur limitée : une longue liste ou une petite fenêtre ne repousse pas le reste de la barre latérale.

### Déplacer des photos vers un autre dossier

Faites glisser une photo ou une sélection sur la ligne d'un autre dossier pour déplacer les fichiers physiques et mettre à jour le catalogue en même temps. La même règle vaut pour les dossiers importés, les dossiers créés par l'application et les dossiers qui contiennent des captures de scanner.

Un nom existant à destination n'est jamais écrasé. Si `frame.tiff` existe, negaflow essaie `frame 2.tiff`, puis `frame 3.tiff`, et ainsi de suite. Le fichier IR associé à une source de scanner suit dans la même transaction.

### Modifications dans le Finder

negaflow surveille les dossiers sources physiques enregistrés. Après un court délai anti-rebond, il ne réexamine que le dossier modifié quand il constate :

- Le déplacement ou le renommage d'un fichier source
- Le déplacement ou le renommage d'un dossier enregistré
- Une nouvelle image directement dans un dossier enregistré

Quand le signet persistant de la source retrouve le nouvel emplacement, la vue existante est rattachée de nouveau. Un dossier déplacé garde son identifiant et sa date d'ajout. Un fichier nouvellement ajouté est importé sans créer de doublon pour les fichiers déjà connus.

C'est une surveillance de dossiers pilotée par les événements, pas un balayage périodique de toute la bibliothèque. Les vues qui ont le même parent physique partagent une seule surveillance, et seuls les dossiers qui signalent un changement sont examinés.

## Développement par dossier

Choisissez un procédé et une cible à côté du titre du dossier, puis sélectionnez **Appliquer**. Il n'y a pas d'interrupteur séparé.

Appliquer refait le rendu de chaque photo du dossier, y compris celles développées plus tôt. Le nouveau procédé et la nouvelle cible sont utilisés, tandis que les autres réglages de l'utilisateur, comme l'exposition et le contraste, restent. Si une vue est déjà en cours de rendu, la tâche du dossier attend la fin de ce rendu.

Une barre de progression, un pourcentage, le nombre de photos terminées et le total apparaissent à côté d'Appliquer. Les gros lots ne gardent qu'autant de travailleurs que d'emplacements de rendu, au lieu de lancer une tâche par photo.

## Redressement et transformation

Ouvrez Géométrie → Recadrage à droite du Développement. Maintenez ⌘ (Ctrl sous Windows), faites glisser le long d'un bord qui doit être horizontal, puis relâchez : la photo tourne pour que la ligne devienne horizontale. Une ligne tracée plus près de la verticale est rendue verticale. Maintenez ⌥ (Alt sous Windows) pour afficher une grille fine sur le recadrage. Les deux touches se changent dans Réglages → Raccourcis et ne peuvent pas être identiques. Sur Mac, ⌃ n'est pas proposé pour la ligne, car ⌃-clic y vaut un clic droit.

La section Transformation se trouve entre Calibrage et Détails et effets. Désactivé laisse la photo telle quelle. Auto, Niveau, Vertical et Complet cherchent une fois les lignes droites de la photo et les corrigent. Niveau ne fait que tourner la photo, Vertical redresse aussi les verticales convergentes, Complet corrige la perspective verticale et horizontale. Auto fait comme Complet mais retient les grandes corrections. Guidé suit 2 à 4 repères que vous tracez sur la photo.

Les curseurs Vertical, Horizontal, Rotation, Aspect, Échelle, Décalage X et Décalage Y s'ajoutent à ce que le mode a trouvé. Un double-clic réinitialise un curseur. Limiter le recadrage coupe le résultat au plus grand rectangle sans coin vide. Désactivé, les coins vides sont blancs à l'écran et dans les fichiers exportés. L'histogramme, l'alerte d'écrêtage, la tonalité automatique et la balance des blancs automatique ne les comptent pas comme photo. La correction suit les rotations de 90° et les retournements, et Réinitialiser tous les réglages l'efface avec le recadrage et le redressement.

## Préréglages et copier-coller

Les réglages de développement comptent sept groupes sélectionnables séparément.

| Groupe | Valeurs |
|---|---|
| Gamma d'entrée | Interprétation du transfert de la source |
| Échelle de base | Échelle de la base du film |
| Base | Type de film et procédé, cible, profil de scanner, base du film, étalonnage de plage par canal, Équilibre auto, Niveaux auto et équilibre neutre |
| Tonalité | Exposition, contraste, densité, hautes lumières, ombres, blancs, noirs et courbes de tonalité |
| Couleur | Température, teinte, profondeur de couleur, vibrance, saturation, mélangeur, étalonnage, calibrage, virage noir et blanc et émulation de film |
| Détail | Grain, netteté, halation, clarté, vignetage, réduction du bruit, intensité GrainMend et réglages locaux |
| Géométrie | Recadrage, rotation, retournements horizontal et vertical, redressement, proportions du recadrage et transformation |

Un collage complet ou un préréglage utilisateur remplace les réglages de développement de la destination. Un collage ciblé remplace les valeurs effectives des groupes choisis et garde les autres. Quand une partie seulement d'un rendu est collée, ses apports de tonalité, de couleur et de texture sont intégrés aux valeurs et la référence au rendu est effacée, pour qu'un ancien rendu ne soit pas ajouté une seconde fois. Coller plusieurs fois les mêmes réglages donne le même état. Les menus, raccourcis et le panneau utilisent la même portée de collage.

Le collage et les préréglages utilisateur s'appliquent à toutes les photos sélectionnées. Une seule annulation ou un seul rétablissement couvre toute la sélection, et Windows valide chaque destination avant d'en modifier une. Les vignettes et l'aperçu actif se rafraîchissent d'après la nouvelle recette. Les fichiers d'origine, les notes et les retouches de défauts liées à la source ne sont pas copiés.

Les préréglages utilisateur enregistrent l'état de développement complet et la géométrie. Les préréglages plus anciens ou les portées de collage sans Géométrie l'incluent par compatibilité. Un nom vide reçoit le premier nom numéroté libre, et l'enregistrement n'écrase jamais un préréglage existant du seul fait que le nom est identique.

## Sans module scanner

Si aucun module scanner n'est installé au démarrage, la barre latérale commune Bibliothèque et Développement n'affiche pas automatiquement l'explication du module manquant, la commande de nouvelle recherche ni le bloc du simulateur. L'import d'images reste disponible.

La nouvelle recherche de scanners et le simulateur existent toujours. Ils restent accessibles depuis le point d'entrée scanner et les Réglages, et l'interface scanner existante apparaît quand un module est installé ou que le simulateur est explicitement activé.

## Mises en page de tirage et nombre de sorties

Le tirage propose huit mises en page : image seule, planche-contact, package d'images, package personnalisé, cyanotype, plaque de verre, gélatino-argentique et filigrane. Les cinq mises en page d'image individuelle montrent une page terminée par photo sélectionnée, en défilement vertical. Le filigrane est une mise en page à part, et les autres gardent leurs commandes habituelles.

Exportation et Exportation rapide comptent les pages terminées. Par exemple, 39 photos dans une planche-contact 6 × 7 donnent un fichier composé, un package d'images à quatre donne 10 pages, le package personnalisé par défaut une page, et les cinq mises en page d'image individuelle 39 fichiers en un lot borné.

L'aperçu du package réutilise une vignette, une image développée ou un aperçu RAW existants et ne crée un petit aperçu rapide que s'il n'y en a aucun. L'export final calcule chaque emplacement d'après les métadonnées de la source, ne développe que les pixels dont cet emplacement a besoin, prépare deux à quatre sources en parallèle et garde le graphe Core Image connecté jusqu'au rendu final de la page. Un contexte de rendu partagé et un budget de 512 Mio de trame source par page empêchent une page de gonfler en un ensemble illimité d'images intermédiaires en pleine résolution.

## Filigrane de tirage

Choisissez Filigrane dans le menu des types de mise en page, après Gélatino-argentique. Il ajoute une bordure sous chaque photo sans la recadrer, et vous pouvez ajouter au-dessus une bordure de même hauteur. Le format du papier photo suit la photo plus ses bordures.

La bordure du bas montre à gauche l'appareil, avec l'objectif en dessous. À droite, elle montre un logo, puis la focale, l'ouverture, la vitesse d'obturation et l'ISO, avec la date en dessous. Activez Logo pour en ajouter un. Sans fichier choisi, le logo de negaflow est utilisé. negaflow ne fournit aucun logo de fabricant : choisissez votre propre fichier JPEG, PNG ou autre image. Les réglages et les modèles ne gardent que le chemin du fichier. Le dessin vérifie le fichier et réutilise le logo en cache tant que sa taille et sa date de modification ne changent pas. Si le fichier a été déplacé ou supprimé, seul le logo est omis, et le point d'état en bas et le rapport de diagnostic le consignent. Les champs vides d'appareil, d'objectif, d'exposition et de date restent vides, et seul le texte saisi est dessiné. Quand le texte est long ou la bordure étroite, comme sur une photo verticale, tous les éléments de la bordure sont réduits du même facteur : le texte ne dépasse jamais de la photo et n'est pas coupé.

La bordure peut être blanche, noire ou un flou de la photo. Sur blanc, le texte est noir avec des deuxièmes lignes grises. Sur noir, tout le texte est blanc. Sur flou, vous choisissez noir ou blanc pour le texte et pour l'histogramme. L'histogramme est dessiné en colonnes de points. Les règles de position du nom et de l'histogramme sont dans [Mises en page de tirage et aperçu C-print](../reference/C_PRINT.md). Le flou et l'histogramme réutilisent une vignette de pellicule valide quand il y en a une, sinon une image réduite de la photo. Les modèles enregistrent la couleur du papier et tous les réglages du filigrane, y compris le texte et le chemin du logo.

## Profils de tirage

Les commandes ICC du Tirage ont des rôles différents.

| Réglage | Aperçu à l'écran | Exportation de tirage | Aperçu de développement |
|---|---|---|---|
| Profil de sortie imprimante | Montre le résultat du tirage | Appliqué à la page terminée | Jamais appliqué |
| Profil d'épreuve C-print | Épreuve écran du procédé du laboratoire et du papier | Non incrusté dans le fichier de livraison | Jamais appliqué |
| Épreuve écran générale | Utilisée dans sa portée d'affichage configurée | Simple aide d'affichage | Suit son propre réglage |

Un profil de sortie imprimante n'est pas appliqué à une source avant que cette source soit dupliquée. La planche-contact, le package d'images ou le package personnalisé est d'abord composé, puis le profil est appliqué une seule fois à la page entière. Les emplacements répétés d'une même source et les mises en page à sources mêlées reçoivent donc la même conversion de sortie.

Le profil d'épreuve C-print est l'aperçu du procédé fourni par le laboratoire. Il n'est jamais substitué en silence au profil de sortie. Les exigences sur les profils et la limite de précision sont dans [Mises en page de tirage et aperçu C-print](../reference/C_PRINT.md).

## Export DNG

Le DNG écrit l'image développée en fichier RVB linéaire 16 bits non compressé (`PhotometricInterpretation = LinearRaw`) dans l'espace colorimétrique de sortie que vous choisissez : sRGB, Display P3 ou Adobe RGB. La tonalité et la couleur sont déjà incrustées, donc les autres applications le lisent comme un fichier référencé en sortie. Le fichier porte le copyright, le scanner, le logiciel, la date et les notes de film selon la même politique de métadonnées que le TIFF. L'EXIF, l'IPTC et le GPS de l'appareil source ne sont pas copiés. Il faut 6 octets par pixel : une vue de 24 mégapixels fait environ 144 Mo.

Le DNG est proposé pour les sources non compressées : TIFF, RAW d'appareil et DNG. Les sources JPEG, PNG et HEIC ne peuvent pas être exportées en DNG. Le développement, la cible `PRINT` et les mises en page de tirage prennent tous en charge le DNG. Le DNG de tirage enregistre la page composée en RVB standard avec une ColorMatrix, et la conversion ICC imprimante est sautée. L'export DNG utilise le dossier choisi dans Exportation et garde l'extension `.dng`. L'opération n'est terminée que lorsque le fichier final est publié et vérifié. exiftool et le décodeur d'images d'Apple lisent le fichier. Le rendu dans d'autres éditeurs RAW n'a pas été mesuré.

## Ce qui modifie la source

| Action | Source dans le Finder | Catalogue et retouches |
|---|---|---|
| `×` du dossier | Conservée | Dossier et photos retirés de la bibliothèque |
| Glisser vers un autre dossier | Déplacée ; un nouveau nom est choisi en cas de collision | Rattachée au nouvel emplacement |
| Déplacer ou renommer dans le Finder | La modification de l'utilisateur est conservée | Rattachée automatiquement par le signet |
| Appliquer le développement du dossier | Conservée | Procédé et cible mis à jour, puis rendu refait |
| Préréglage ou copier-coller | Conservée | Valeurs de développement et de géométrie choisies mises à jour |
| Exportation de tirage | Conservée | Un fichier de sortie et un relevé de rendu distincts sont créés |

## Contrôle d'une grande bibliothèque

Au-delà de 256 photos, la pellicule ne fait plus de longs sauts de défilement automatiques après chaque changement de sélection. Les cartes visibles et les lignes de dossier sont créées à la demande.

Le test de charge de 2 000 vues importe des jeux de pixels de 24 MP, 40 MP, 60 MP, 3200 DPI et 4800 DPI dans 50 dossiers. Il mélange tous les procédés et cibles, garde plus de la moitié de négatifs couleur, applique des changements de recadrage et d'orientation, puis vérifie le développement, les vignettes et l'aller-retour du catalogue. À lancer depuis `negaflow-mac/` :

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

Le test de charge est à activer soi-même et est ignoré par les exécutions ordinaires de `swift test`.
