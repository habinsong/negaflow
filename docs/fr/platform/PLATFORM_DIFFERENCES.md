# Ce qui diffère entre les versions macOS et Windows

[Accueil de la documentation](../README.md)

negaflow existe en deux exemplaires, un pour macOS et un pour Windows. Ils ne partagent aucun code source, et chacun est écrit à la manière de son système.

## Pourquoi deux versions

Un seul code multiplateforme imposerait une seule boîte à outils et ses compromis sur les deux systèmes : menus et boîtes de dialogue au comportement bizarre, une couche de conversion de couleur de plus, des fenêtres qui ne ressemblent pas au système. Écrire chaque côté de façon native double à peu près le travail, puisque chaque fonction est construite et testée deux fois. En échange, chaque version se comporte comme on l'attend sur son système.

## Ce qui est identique

L'image. La même numérisation donne le même résultat des deux côtés.

La version macOS rend un jeu d'images de référence dans `docs/verification/macos-golden`. Git ignore ce dossier : les images n'existent qu'à l'endroit où elles ont été rendues. Les tests du moteur Windows en lisent des copies et comparent les valeurs de pixels, donc une dérive du moteur Windows fait échouer les tests.

Il en va de même pour :

- La mesure de la base du film et l'inversion
- Toutes les cibles de développement : `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`, `CS`
- Tonalité, courbes, TSL, étalonnage, virage en noir et blanc
- La détection et la réparation GrainMend, y compris le chemin infrarouge
- Les mises en page de tirage et la géométrie des pages
- Le nommage des fichiers exportés, l'écriture EXIF et la politique des métadonnées
- Le format du catalogue (`library.sqlite`)

## Ce qui diffère

### Gestion des couleurs

macOS utilise ColorSync, Windows utilise ICM. Les deux prennent les mêmes profils ICC et donnent les mêmes valeurs à l'arrondi près. Les tests de parité couvrent ce point, car c'est celui qui dérive le plus facilement sans bruit.

### Graphismes

macOS exécute la chaîne de développement sur Core Image. Windows l'exécute sur des shaders de calcul Direct3D, avec un repli sur le CPU quand le chemin GPU n'est pas disponible.

### Où se trouvent les fichiers

| | macOS | Windows |
|---|---|---|
| Application | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Bibliothèque et réglages | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |

### Installation et désinstallation

macOS fournit un PKG qui place l'application dans `/Applications` ; pour la supprimer, glissez-la dans la corbeille. Windows fournit un programme d'installation qui écrit dans votre dossier utilisateur sans droits administrateur. La désinstallation passe par `Uninstall negaflow` dans le menu Démarrer ou par Paramètres, et retire le dossier de l'application, l'entrée du menu Démarrer et l'enregistrement du paquet.

### Ligne de commande

macOS fournit `negaflow`, une CLI complète qui détecte les scanners, développe des fichiers, lance GrainMend et mesure les performances. Windows fournit `negaflow-cli.exe`, un outil de diagnostic plus petit qui vérifie ce que le moteur fait d'un seul fichier. Il prend des options, pas des sous-commandes.

### Signature

Aucune des deux versions n'est signée avec un certificat de développeur payant, donc les deux systèmes avertissent au premier lancement. La version Mac est signée en ad hoc et non notariée : autorisez-la avec Ouvrir quand même dans Confidentialité et sécurité. Le programme d'installation Windows n'est pas signé : cliquez sur Informations complémentaires dans SmartScreen, puis exécutez-le.

## Scanners

Le module de scanner est un projet GPL séparé, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), qui existe pour les deux systèmes. Il tourne dans son propre processus et dialogue en JSON : negaflow ne contient aucun code SANE sur aucune des deux plateformes. Sous Windows, il passe par le chemin de pilotes de scanner que Windows fournit déjà, donc VueScan et SilverFast continuent de fonctionner sur la même machine.

## Les garder alignées

Chaque fonction arrive d'abord sur macOS, puis sur Windows en suivant le comportement réel de macOS. Là où la sortie peut être mesurée, les images de référence macOS décident si Windows est correct. En cas de désaccord, macOS a raison et le bug est du côté Windows.
