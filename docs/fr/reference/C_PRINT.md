# Mises en page de tirage et aperçu C-print

[Accueil de la documentation](../README.md)

L’espace Impression réunit la mise en page, l’export de la page et l’aperçu du procédé de sortie. Il
propose l’image unique, la planche-contact, le package d’images et le package personnalisé.

## Planches-contact

Une nouvelle planche-contact utilise par défaut un fond noir, 6 colonnes × 7 lignes et des
espacements horizontaux et verticaux de 2 mm. Le fond peut être noir ou blanc ; les légendes, textes
personnalisés, repères de coupe et contours adoptent automatiquement une couleur contrastée.

Les marges, le nombre de lignes et de colonnes et les deux espacements partagent le même calcul
physique. Une combinaison trop grande est limitée au maximum valide au lieu de casser l’aperçu.
L’orientation automatique dépend de la grille et non de la première photo. **Ajuster** conserve
l’image entière et peut laisser de l’espace dans la cellule ; **Remplir la cellule** recadre l’image
et rend les gouttières visibles régulières.

Les légendes peuvent afficher le nom du fichier, le numéro de vue original, un numéro d’ordre
repartant de 1, la note ou un texte personnalisé. Les légendes par image s’alignent à gauche, au
centre ou à droite. Plusieurs zones de texte personnalisé peuvent être ajoutées, chacune avec son
texte, son alignement, sa position, sa largeur et sa hauteur.

## Mises en page individuelles et historiques

Image unique, cyanotype, plaque de verre et gélatino-argentique créent une page par photo
sélectionnée. Avec plusieurs photos, les pages se suivent verticalement et se parcourent par
défilement au lieu d’être forcées sur une seule feuille. Le cyanotype traduit la luminance en
monochrome bleu, la plaque de verre affiche un négatif monochrome et le gélatino-argentique un
positif monochrome neutre.

Ces trois mises en page reprennent le papier, l’orientation, les marges, la sortie et l’inspecteur
d’Image unique, et leur rendu est inclus dans Export et Exportation rapide. Ce sont des
présentations visuelles assumées, pas une reconstruction mesurée d’une chimie, plaque, papier ou
condition d’observation historique précise.

## Exporter le tirage

**Exporter le tirage**, sous Exportation rapide, rend le format et l’orientation du papier, les
marges, la mise en page, le fond noir ou blanc, les légendes, les textes personnalisés et les
repères de coupe. Le format de fichier, le DPI, le dossier, le nom et l’espace colorimétrique de
livraison viennent des réglages d’export. Les aides d’écran — avertissement de gamut, simulation
d’épreuvage et reflet de surface — ne sont pas intégrées au fichier.

### Nombre de pages et rendu

Le compteur indique les pages terminées. Une planche-contact 6 × 7 de 39 photos produit une page
composée ; un package de quatre images par page en produit 10 ; le package personnalisé par défaut
en produit une ; et chaque mise en page individuelle produit 39 fichiers avec le même ordonnanceur
par lots limité que l’Exportation rapide.

L’aperçu de package ne génère pas deux aperçus pleine résolution, interactif puis stabilisé, pour
chaque photo. Il réutilise les images disponibles et ne crée qu’un aperçu rapide de taille vignette
pour un élément manquant. L’export final déduit la mise en page des métadonnées source, ne développe
que les pixels nécessaires à chaque emplacement et prépare deux à quatre sources uniques à la
fois. Le contexte Core Image partagé, le graphe conservé jusqu’à l’écriture de la page et le budget
de 512 MiB de rasters source par page limitent la mémoire sans modifier le rendu ni le contrat.

### Profil de sortie imprimante

Le profil de sortie imprimante choisi dans l’espace Tirage fait partie du fichier exporté. negaflow
compose d’abord la page entière, puis applique le profil une seule fois à la page terminée. Toutes
les cases d’un package sont ainsi traitées, qu’elles répètent la même photo ou mélangent plusieurs
photos.

Ce profil ne modifie ni la Bibliothèque ni l’aperçu Développement. Son effet reste limité à l’aperçu
Tirage et à l’export du tirage.

## Utilisation de C-print

Le procédé de sortie peut être standard ou C-print. C-print mémorise le laboratoire, le papier et
la surface, puis utilise le profil ICC RVB fourni par le laboratoire pour une épreuve écran. Sans
profil mesuré, negaflow n’applique aucun rendu « C-print » générique.

1. Dans l’espace Impression, choisissez **C-print** comme procédé de sortie.
2. Saisissez le laboratoire et le papier, puis choisissez la surface.
3. Sélectionnez le profil ICC RVB fourni pour ce laboratoire, ce papier et cette machine.
4. Activez l’aperçu du tirage. La simulation du papier et du noir ainsi que l’avertissement de gamut
   se trouvent dans Avancé.

Sans profil ICC RVB valide, les réglages de destination restent enregistrés, mais l’aperçu du tirage
est indisponible. Les profils CMJN et device-link ne sont pas acceptés par ce chemin RVB.

## Contrat colorimétrique

Le profil ICC d’épreuvage C-print est réservé à l’écran. Il ne modifie ni les pixels ni le profil
intégré au fichier exporté. Si aucun profil de sortie imprimante distinct n’est choisi, l’export du
tirage utilise l’espace colorimétrique de livraison indiqué dans les réglages d’export. Un profil
distribué pour l’épreuvage ne devient donc jamais silencieusement un profil de livraison.

L’ancien target de développement `PRINT` reste séparé. Il exige toujours un profil ICC RVB de classe
imprimante valide et convertit la sortie au moyen de ce profil.

## Limites de précision

L’aperçu applique la transformation ICC et peut simuler le blanc du papier, le point noir et les
couleurs hors gamut. Sa précision dépend d’un écran étalonné et d’un profil à jour pour le procédé
exact du laboratoire. Il ne prédit ni l’éclairage d’observation, ni la dérive chimique, ni
l’étalonnage de la machine, ni les variations de lot du papier. negaflow n’intègre et n’invente aucun
profil de laboratoire.
