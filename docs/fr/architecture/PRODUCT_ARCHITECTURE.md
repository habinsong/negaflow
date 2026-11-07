# Architecture produit

[Accueil de la documentation](../README.md)

negaflow est une application macOS et Windows. Vous importez ou numérisez des images de film, puis vous passez par l'inversion, le développement, GrainMend, la sortie et la conservation. Chaque retouche est tenue à part de l'original.

> [!IMPORTANT]
> Les originaux, l'historique des retouches, les caches et les fichiers de sortie sont des matières différentes. Perdre un cache ne doit pas faire perdre l'original ni l'historique des retouches, et un export échoue si un résultat nécessaire ne peut pas être reconstruit.

## Règles de sécurité immuables

1. Les images originales et les fichiers annexes tiers ne sont jamais écrasés automatiquement.
2. Retirer quelque chose de la bibliothèque et mettre l'original à la corbeille sont deux actions distinctes.
3. L'écran du scanner n'affiche que ce que le module a déclaré.
4. Le scanner de démonstration n'est utilisé que si vous le choisissez explicitement.
5. Si un résultat retouché ne peut pas être reconstruit, l'original n'est pas exporté à sa place.
6. Une longue tâche revérifie la vue, la version de retouche et la session juste avant d'appliquer son résultat.
7. Un cache doit pouvoir être reconstruit à partir de l'original et de l'historique des retouches.
8. Les profils, les lots de sortie et les archives ne sont publiés qu'après réussite des contrôles requis.

## Modules

`negaflowApp` et `negaflowCLI` utilisent tous deux `Chromabase` et `ScannerKit`. `Chromabase` travaille sur les images et les métadonnées, et `ScannerKit` dialogue avec le module scanner externe.

### `Chromabase`

Le Chroma Engine et le cœur du traitement d'image.

- Lecture des images et gestion de l'orientation
- Mesure de la base du film
- Développement des négatifs et des positifs
- Tonalité, couleur et retouches locales
- Profils de film, de rendu et de scanner
- GrainMend RVB et IR
- Histogramme et mesure de la couleur
- Encodage de sortie et métadonnées

Plus de détails :

- [Chroma Engine](../product/CHROMA_ENGINE.md)
- [GrainMend](../product/GRAINMEND.md)

### `ScannerKit`

Il détient le contrat qui relie un module externe.

- Identifiant et capacités du scanner
- JSON des requêtes et des réponses
- Exécution du processus externe, délais et annulation
- Propriétaire, droits, approbation et empreinte du module
- Contrôle de la sortie temporaire, puis publication du fichier final
- Sessions de numérisation et historique des tâches
- Le scanner de démonstration à activer soi-même

L'implémentation SANE se trouve dans un projet GPL séparé, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane). L'application et le module dialoguent uniquement en JSON et par la CLI.

### `negaflowCLI`

Utilise le même moteur et le même `ScannerKit` que l'interface graphique.

- Recherche des scanners, contrôle des capacités, numérisation
- Développement de plusieurs images
- Liste des profils de scanner
- `defect-bench` de GrainMend
- Comparaison IT8 et relative entre scanners
- Autotests et automatisation JSON

### `negaflowApp`

L'interface utilisateur, construite avec SwiftUI et AppKit.

- Bibliothèque, développement, tirage, canevas
- Numérisation, GrainMend, export
- Versions, réglages, raccourcis
- Catalogue, cache, sauvegarde, archive de conservation
- Une fenêtre À propos localisée dont la version du produit vient de la ressource de version commune

## Parcours de l'utilisateur

1. Importer ou numériser.
2. Organiser la bibliothèque.
3. Fixer le type de film et la base.
4. Développer dans Chroma Engine, réparer avec GrainMend, ou ouvrir des branches avec les versions et les copies virtuelles.
5. Contrôler, tirer ou exporter vers des fichiers image, des fichiers annexes et des relevés de rendu, ou vers une archive de conservation.

Chaque étape laisse l'original intact et ajoute au catalogue et à l'historique des retouches.

## Entrée et originaux

### Importer des fichiers

La voie d'entrée par défaut. Elle prend en charge TIFF, JPEG, PNG et les RAW d'appareil que l'Image I/O de macOS sait lire. L'ICC intégré et l'orientation sont lus, et l'identifiant d'origine entre dans le catalogue.

### Numérisation

Un module installé peut déclarer ces capacités :

- Résolution et profondeur de bits
- Zone de numérisation et aperçu
- Exposition
- IR
- Comportement des lots et du porte-film

L'application n'invente jamais une capacité à partir d'une table de noms de modèles. Quand une numérisation se termine, les réglages réellement appliqués par le module et le fichier de sortie sont revérifiés.

### Identifiant d'origine

Un chemin de fichier seul n'identifie pas un original. Les valeurs dont le contrat actuel a besoin sont conservées : observations du fichier, taille en octets, date de modification, SHA-256 et signet persistant.

Si un fichier a été déplacé, le chemin ne change que si vous le rattachez vous-même ou si la récupération par signet réussit.

## Catalogue

Le stockage principal est `library.sqlite`. L'ancien `library.json` sert à reprendre des données anciennes confirmées, ou à écrire une sauvegarde déplaçable d'une machine à l'autre. Les deux stockages ne sont jamais mis à jour en même temps.

Ce qui entre dans SQLite :

- Vues et originaux
- Bobines, dossiers, collections, recherches
- Ordre et tâches de numérisation
- Valeurs de développement et historique des retouches par version

Ce qui n'y entre pas :

- Pixels des originaux
- Vignettes et aperçus
- Caches GrainMend

### Migration depuis le JSON

1. Vérifier le schéma et la santé du JSON existant.
2. Conserver une copie de récupération.
3. L'écrire dans un SQLite temporaire en une seule transaction.
4. Comparer le catalogue avant et après.
5. Vérifier l'intégrité SQLite et les conditions de sécurité de l'application.
6. Ne basculer le stockage principal que si tout concorde.

Un JSON en échec n'est pas traité comme un catalogue vide. Les chiffres sont dans [Stockage du catalogue](CATALOG_STORAGE.md).

## Bibliothèque

Organisation :

- Dossiers, bobines, collections manuelles, collections intelligentes, recherches enregistrées, piles
- Notes par étoiles, retenue et rejet, étiquettes de couleur
- Grille, comparaison, vue d'ensemble
- Examen des candidats en double

Dans la vue par dossiers, chaque dossier affiche un bandeau avec un triangle de dépliage, le dossier, le nom, le nombre, le procédé de développement, la cible et appliquer. Le bandeau replie les vignettes en dessous. Les dossiers repliés sont mémorisés d'un lancement à l'autre, séparément de la liste de fichiers de la barre latérale.

La vue par dossiers utilise une seule grille, chaque dossier étant une section dont le bandeau est l'en-tête. Gardez cette structure. Empiler une grille distincte par dossier obligerait la mise en page à calculer la hauteur totale de chaque dossier visible et à créer toutes ses cartes d'un coup, alors qu'une grille unique crée les cartes ligne par ligne à mesure qu'elles entrent dans la vue. C'est ce qui garde le défilement fluide sur plusieurs centaines de photos.

Plusieurs copies virtuelles peuvent partager un original. Les références à un original sont vérifiées avant suppression. Retirer quelque chose de la bibliothèque ne modifie que des références du catalogue, et mettre à la corbeille est une autre action.

Les retouches sont préservées quand un disque externe est déconnecté. L'original est marqué hors ligne, et vous le rattachez par fichier ou par dossier. Si l'identifiant n'est pas celui attendu, rien n'est échangé automatiquement.

Chaque dossier source physique enregistré a un observateur de système de fichiers. Les événements sont brièvement regroupés, puis seul le dossier modifié est réexaminé. Le rattachement par signet conserve l'identifiant du dossier du catalogue quand le Finder déplace ou renomme une source, et les images nouvellement ajoutées directement dans un dossier sont importées sans interrogation périodique ni nouvel examen de toute la bibliothèque.

## Développement et GrainMend

Chaque vue porte :

- L'identifiant d'origine et le type de film
- La base du film
- Les valeurs de développement
- L'historique des retouches GrainMend
- L'historique des versions
- L'état d'export

Pendant que vous ajustez, un aperçu de résolution plus basse est utilisé. Un résultat terminé n'arrive à l'écran que si l'identifiant de la vue et la version de retouche correspondent encore à la sélection actuelle.

Choisir une autre photo lance son rendu stabilisé sans la pause de retouche. Sous macOS :

- Une fois un négatif RAW d'appareil stabilisé, le RAW visible suivant peut être décodé en arrière-plan. Un seul voisin est préparé, dans le cache maître existant (jusqu'à 160 Mio). Une retouche, une autre sélection ou une pression mémoire annule ce travail, et choisir la photo déjà en préparation partage son décodage.
- Une sélection à froid de RAW d'appareil déballe les données du capteur une seule fois. Quand la mosaïque le permet, un aperçu RVB d'appareil provisoire apparaît avant la fin du dématriçage canonique. Le cache maître reste désactivé sous pression mémoire, et évincer une vue abandonne aussi son maître RAW.
- Une sélection à froid de TIFF partage une même source décodée entre l'aperçu interactif et l'aperçu stabilisé et la réduit sur le GPU. Les aperçus RAW Apple, DNG compris, gardent un seul `CIRAWFilter` pour les deux passes.
- Les TIFF RAW corrigés sont écrits quand leurs tampons de pixels quittent la mémoire, et non après chaque retouche. Le nettoyage du disque garde les fichiers récents dans une limite, protège les fichiers en cours d'usage et supprime au lancement suivant les caches laissés par la session précédente. Les recettes de retouche restent dans les fichiers annexes.

Sous Windows, les vignettes JPEG utilisent un budget d'octets LRU et les aperçus BGRA le reste du budget d'affichage géré, et une pression mémoire critique abandonne les JPEG inactifs. Les tampons de transit D3D ont une limite de cache, que libèrent les signaux de manque de mémoire, la fin d'un export et la réinitialisation de l'appareil.

L'export n'enregistre pas la bitmap d'aperçu à l'écran. Il reconstruit l'image pleine résolution à partir de l'original et des valeurs de retouche qu'il a figées.

GrainMend garde automatique, guidé, pinceau, tampon de clonage et IR dans une liste ordonnée. Les caches sont des fichiers dérivés. Si un résultat ne peut pas être reconstruit à partir de l'original et de l'historique des retouches, l'export échoue.

Plus de détails dans [GrainMend](../product/GRAINMEND.md).

## Versions

- Historique et instantané : enregistrez vous-même un état de développement, puis comparez-le ou revenez-y.
- Copie virtuelle : une autre branche de retouches sans dupliquer le fichier original.
- Copier-coller : collez une portée choisie, comme la tonalité, la couleur, le détail ou la géométrie. Les masques qui exigent les coordonnées d'origine voient leurs conditions de sécurité vérifiées.

## Exportation

Au départ, ces valeurs sont figées en un seul lot :

- Identifiant d'origine
- Historique de développement et de retouches GrainMend
- Octets et SHA-256 du profil de scanner
- Réglages de sortie et politique des métadonnées
- Nom de fichier et destination

Arrêter puis reprendre un export utilise le même lot.

### Plusieurs fichiers de sortie

Un export peut produire ensemble un JPEG/TIFF, un fichier annexe, un XMP et `-main-flat`.

1. Vérifier d'avance la destination et les conflits de noms.
2. Écrire tous les fichiers dans un dossier temporaire.
3. Rouvrir l'image et vérifier ses dimensions en pixels.
4. Calculer les tailles en octets et les SHA-256.
5. Écrire le fichier annexe et le relevé de rendu.
6. Laisser un enregistrement de validation.
7. Déplacer tout le lot vers son emplacement final.
8. En cas d'échec, annuler ou nettoyer à l'exécution suivante.

Un jeu de fichiers partiel n'est jamais marqué comme réussi.

### Relevé de rendu v3

Il consigne les liens SHA-256 entre :

- Les octets de l'original
- L'entrée de rendu réellement utilisée
- L'historique de développement et de GrainMend
- Le profil de scanner
- Les versions du décodeur et du moteur de rendu
- Les octets de sortie, les dimensions en pixels et le format

Il n'y a ni signature numérique ni certificat : ce n'est donc pas du C2PA Content Credentials. Plus de détails dans [Manifeste de rendu](../reference/RENDER_MANIFEST.md).

## Tirage et épreuve écran

Mises en page prises en charge :

- Image seule
- Planche-contact
- Package d'images
- Package personnalisé
- Cyanotype
- Plaque de verre
- Gélatino-argentique
- Filigrane

L'image seule et les trois mises en page historiques produisent une page empilée verticalement par photo sélectionnée. La planche-contact, le package d'images et le package personnalisé comptent et exportent plutôt leur nombre de pages terminées. Pour 39 photos, cela donne une page de planche-contact 6 × 7, 10 pages de package d'images à quatre, une page de package personnalisé par défaut, ou 39 fichiers individuels.

L'aperçu du package réutilise les vignettes et les images développées disponibles et ne fabrique un petit aperçu rapide que s'il en manque un. L'export final calcule les emplacements d'après les métadonnées, ne développe que les pixels dont chaque cellule a besoin, prépare deux à quatre sources distinctes à la fois, garde le graphe Core Image connecté jusqu'à l'écriture de la page et applique un budget de 512 Mio de trame source par page.

Chaque emplacement d'un package respecte la vue qui lui est affectée. L'ICC de sortie imprimante est appliqué une seule fois, à la page finale complète, une fois la mise en page terminée : les packages à emplacements répétés ou à sources mêlées suivent donc le même contrat de sortie. Il ne change jamais l'aperçu de la Bibliothèque ou du Développement, et ni le TIFF de numérisation d'origine ni `-main-flat` ne reçoivent de profil d'imprimante.

Sans ICC RVB d'imprimante valide, aucun autre profil n'est substitué. Les octets et le SHA-256 du profil choisi entrent dans le relevé de sortie.

## Archive de conservation

Ce qui entre dans `.negaflowarchive` :

- Le JSON de catalogue portable
- Les fichiers originaux
- Les originaux IR
- L'historique GrainMend nécessaire
- La relation entre les copies virtuelles et l'original qu'elles partagent

Les vignettes, aperçus, caches GrainMend et fichiers exportés peuvent être reconstruits, ils restent donc dehors. L'archive suit la structure BagIt de la RFC 8493 avec une liste SHA-256, et chaque fichier et chaque relation sont vérifiés avant que le lot soit déplacé vers son emplacement final.

- [Archive de bibliothèque](LIBRARY_ARCHIVE.md)
- [RFC 8493](https://www.rfc-editor.org/info/rfc8493/)
- [PREMIS](https://www.loc.gov/standards/premis/)

La conservation à long terme demande aussi d'autres supports, une copie hors site et des contrôles d'empreintes réguliers.

## Sécurité des modules scanner

Quand un module est trouvé, on vérifie :

- Si l'utilisateur courant en est propriétaire
- Si un groupe ou un autre utilisateur peut y écrire
- S'il s'agit d'un lien symbolique
- L'identifiant et le SHA-256 de la fiche et de l'exécutable
- Si l'identifiant que vous avez approuvé est toujours celui que vous avez devant vous

Si le fichier a changé, l'approbation précédente n'est pas réutilisée.

Le protocole v2 utilise un identifiant de requête et un numéro de séquence, et exige exactement un résultat final. La taille de sortie a un plafond, et après un dépassement de délai ou une annulation, le processus et ses tubes sont nettoyés.

Un module ne publie jamais lui-même un fichier à l'emplacement final. L'application lui remet un emplacement temporaire, vérifie le format, la taille, l'identifiant et les réglages réellement appliqués, puis déplace le fichier dans le stockage de l'application.

Le contrat complet est dans [Architecture des plugins scanner](SCANNER_PLUGINS.md).

## Limites de performance

Images :

- Un seul `CIContext` partagé
- Un graphe d'image calculé quand il le faut
- Réglage en basse résolution séparé de la sortie en pleine résolution
- Annulation, et refus des résultats périmés
- GrainMend traité par zone, tuile et pièce
- Caches abandonnés sous pression mémoire

Catalogue :

- Transactions SQLite et lignes par entité
- Sauvegarde par réplication
- Contrôles d'intégrité
- Mesuré à 50 000 vues

Aujourd'hui, tout le catalogue est chargé en mémoire au démarrage. Sur le même Mac, la lecture de SQLite a pris environ 7,4 secondes, proche du JSON. Lire seulement les lignes nécessaires, via un index, est l'étape suivante.

Le dépôt utilise de larges limites de performance pour détecter les grosses régressions. Elles ne garantissent pas la réactivité sur tous les Mac pris en charge.

## Ce qui est vérifié

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/run-app.sh build
```

Ce que les contrôles automatiques ne tranchent pas :

- Les vrais scanners et modules
- Le vrai alignement RVB/IR et la compatibilité avec les films
- La qualité de GrainMend à 100 %
- L'interface, y compris la taille d'écran et l'accessibilité
- Developer ID, notarisation, Gatekeeper
- L'installation sur un Mac vierge
- Les performances sur un autre Mac

## Guide des documents

| Ce que vous voulez | Document |
|---|---|
| Inversion et développement | [Chroma Engine](../product/CHROMA_ENGINE.md) |
| Réparation des défauts | [GrainMend](../product/GRAINMEND.md) |
| Profils de film | [Profils de film](../product/FILM_PROFILES.md) |
| Connecter un scanner | [Architecture des plugins scanner](SCANNER_PLUGINS.md) |
| Critères de publication des profils | [Contrôle qualité des profils scanner](../reference/PROFILE_QUALITY_GATE.md) |
| Archive de conservation | [Archive de bibliothèque](LIBRARY_ARCHIVE.md) |
| Liens d'empreintes des fichiers de sortie | [Manifeste de rendu](../reference/RENDER_MANIFEST.md) |
