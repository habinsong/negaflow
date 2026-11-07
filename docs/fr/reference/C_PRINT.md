# Mises en page de tirage et aperçu C-print

[Accueil de la documentation](../README.md)

Le tirage propose huit mises en page : image seule, planche-contact, package d'images, package personnalisé, cyanotype, plaque de verre, gélatino-argentique et filigrane.

## Planches-contact

- Une nouvelle planche-contact démarre sur une feuille noire, en 6 colonnes × 7 lignes avec des espaces de 2 mm. Toutes les autres mises en page démarrent sur une feuille blanche. Chaque mise en page peut passer sa feuille entre noir, gris et blanc, et les légendes, textes personnalisés, repères de coupe et contours de page prennent d'eux-mêmes une couleur contrastée.
- Les marges, le nombre de lignes et de colonnes et les espaces suivent un seul contrat de mise en page physique. Une combinaison impossible est ramenée au plus grand espacement valide plutôt que de casser l'aperçu. L'orientation automatique suit la grille. **Ajuster** garde la photo entière visible et peut laisser du vide dans sa cellule. **Remplir la cellule** recadre chaque photo à la cellule commune et uniformise les gouttières.
- Les légendes peuvent être le nom de fichier, le numéro de vue d'origine, un numéro d'ordre (à partir de 1 dans l'ordre d'image actuel), la note ou un texte personnalisé. Toute police Mac installée peut être choisie, et l'aperçu comme l'export utilisent la même. Les légendes par image s'alignent à gauche, au centre ou à droite. Le texte personnalisé accepte plusieurs zones indépendantes, chacune avec son texte, son alignement, sa position, sa largeur et sa hauteur.

## Réglages du papier et règles

Toutes les mises en page partagent les mêmes réglages de papier. Le catalogue comprend les formats photo courants en pouces de 3,5 × 5 à 24 × 36, Letter, Tabloid, A3+, ISO A1–A6 et ISO B1–B6. La surface se trouve sous la couleur de feuille et propose Mat (par défaut), Brillant, Lustré et Soie.

Les règles sont désactivées par défaut. Les activer ajoute un sélecteur po/cm sous l'interrupteur, une règle horizontale au-dessus de la page et une règle verticale à sa gauche. Les pouces ou centimètres entiers sont numérotés, avec des graduations plus fines entre eux.

## Mises en page individuelles et historiques

Image seule, cyanotype, plaque de verre et gélatino-argentique produisent une page par photo sélectionnée. Plusieurs photos sélectionnées s'affichent en pile verticale. Le cyanotype fait correspondre la luminance à une image monochrome bleue, la plaque de verre montre un négatif monochrome et le gélatino-argentique un positif monochrome neutre.

Ces trois styles utilisent les mêmes réglages de papier, d'orientation, de marges, de sortie et d'inspecteur que l'image seule, et ils sont rendus dans l'export et l'exportation rapide. Ce sont des styles visuels voulus, pas une reconstitution mesurée d'une chimie, d'une plaque, d'un papier ou d'une condition de visionnage historiques.

## Filigrane et modèles de mise en page

Le filigrane est un type de mise en page à part dans le menu. Le choisir règle le format de papier sur Proportions de la photo (un autre format reste possible ensuite) et ajoute des bordures autour de la photo. Le menu de position du nom est toujours disponible : Bas centre, Haut gauche, Haut centre ou Haut droite, et une position haute active la bordure du haut. Les vitesses d'obturation ne reçoivent pas de guillemet ajouté, et les champs de texte vides restent vides. Le texte du nom est centré dans sa position. Quand le nom et l'histogramme partagent une position, l'histogramme se place au-dessus du nom et chacun est centré.

Un modèle de mise en page rétablit la mise en page, les réglages de papier, la couleur de feuille et les réglages de filigrane, puis rafraîchit l'aperçu. Les réglages de DPI et de règles restent tels quels. Les modèles enregistrés avant l'existence de ces champs gardent la couleur de feuille et le filigrane actuels. L'emplacement des champs et les règles sur la source DNG et l'espace colorimétrique sont dans [De la bibliothèque au tirage](../product/WORKFLOW.md).

## Exportation de tirage

**Exportation de tirage**, juste sous Exportation rapide, rend le format de page, l'orientation, les marges, la mise en page, la couleur de feuille, les légendes, le texte personnalisé et les repères de coupe actuels, avec le format, le DPI, le dossier, le nommage et l'espace colorimétrique de livraison affichés dans Exportation. Les aides réservées à l'écran ne sont pas incrustées dans le fichier : avertissements de gamut, simulation d'épreuve écran et brillance de surface du papier. Pendant que l'une ou l'autre voie d'exportation de tirage s'exécute, le panneau Exportation affiche le nombre de pages terminées, une barre de progression linéaire et un pourcentage au lieu d'un indicateur sans fin.

### Nombre de pages et rendu

Le compte est celui des pages terminées. Une planche-contact 6 × 7 de 39 photos exporte une page composée, un package d'images à quatre exporte 10 pages, le package personnalisé par défaut exporte une page, et chaque mise en page d'image seule exporte 39 fichiers par le même ordonnanceur de lots borné que l'exportation rapide.

L'aperçu du package ne construit pas, pour chaque photo, d'aperçu interactif ni d'aperçu stabilisé en pleine résolution. Il réutilise les images disponibles et crée seulement un aperçu rapide de la taille d'une vignette pour un élément manquant. L'export final déduit la mise en page des métadonnées de la source, ne développe que les pixels dont chaque emplacement a besoin, prépare deux à quatre sources distinctes à la fois et garde le graphe Core Image connecté jusqu'à l'écriture de la page. Le contexte de rendu partagé et un budget de 512 Mio de trame source par page bornent la mémoire sans changer la mise en page visible ni le contrat de sortie.

### Profil de sortie imprimante

Le profil de sortie imprimante choisi dans Tirage fait partie du résultat exporté. negaflow compose d'abord la page entière, puis applique le profil une seule fois à la page terminée, ce qui couvre chaque emplacement d'un package d'images ou d'un package personnalisé, qu'il répète une photo ou en mélange plusieurs. Le profil n'agit pas sur l'aperçu de la Bibliothèque ou du Développement, seulement sur l'aperçu de tirage et l'exportation de tirage.

## Utilisation de C-print

Le procédé de sortie est Standard ou C-print. C-print enregistre le laboratoire et le papier de destination et utilise un profil ICC RVB fourni par ce laboratoire pour une épreuve écran. Le contrôle de surface reste dans Mise en page pour tous les procédés et toutes les mises en page. Sans profil mesuré, negaflow n'applique aucun « look C-print » générique.

1. Ouvrez l'espace Tirage et choisissez **C-print** sous Procédé de sortie.
2. Saisissez le laboratoire et le papier. Choisissez la surface sous Mise en page si besoin.
3. Choisissez le profil ICC RVB fourni pour ce laboratoire, ce papier et cette machine.
4. Activez l'aperçu de tirage. La simulation du papier et de l'encre noire et l'avertissement de gamut sont sous Avancé.

Sans profil ICC RVB valide, les réglages de destination sont quand même enregistrés, mais l'aperçu de tirage reste indisponible. Les profils CMJN et device-link ne sont pas acceptés par cette voie d'aperçu RVB.

## Contrat colorimétrique

Le profil ICC d'épreuve C-print sert uniquement à l'épreuve. Il modifie l'aperçu à l'écran, pas les pixels ni le profil intégré d'un fichier exporté. L'exportation de tirage utilise l'espace colorimétrique de livraison choisi dans les réglages d'export, sauf si un profil de sortie imprimante est sélectionné ; un profil d'épreuve de laboratoire n'est donc jamais utilisé en silence comme profil de livraison. La cible de développement `PRINT` est distincte : elle exige un profil ICC RVB de classe imprimante valide et convertit la sortie par ce profil.

## Limites de précision

L'aperçu inclut la transformation ICC et peut simuler en option le blanc du papier, le point noir et les couleurs hors gamut. Sa précision dépend d'un écran étalonné et d'un profil à jour pour le procédé exact du laboratoire. Il ne peut pas prédire la lumière de visionnage, la dérive des bains, l'étalonnage de la machine ni les variations d'un lot de papier. negaflow ne fournit ni n'invente de profil de laboratoire.
