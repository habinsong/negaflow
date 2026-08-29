# Ce qui diffère entre les versions macOS et Windows

[Accueil de la documentation](../README.md)

negaflow existe en deux exemplaires. La version macOS est écrite en Swift et SwiftUI
sur Core Image. La version Windows est en C# et WinUI 3 avec un moteur C++ sur Direct3D.
Les deux ne partagent aucun code source.

Cette page dit ce que cela change en pratique : ce qui est identique, ce qui a l'air
différent, et ce qu'un seul des deux côtés sait faire.

## Pourquoi deux

Une seule base de code pour les deux systèmes aurait voulu dire choisir une boîte à outils
et accepter le résultat partout. Des menus au mauvais endroit, des sélecteurs de fichiers
au comportement bizarre, une couleur qui passe par une couche de traduction de plus, et une
fenêtre qui ne ressemble jamais tout à fait au reste du système.

Écrire chaque côté selon sa propre plateforme coûte à peu près le double de travail, et
chaque fonction se construit et se teste deux fois. En échange, les deux versions se
comportent comme les gens l'attendent sur le système qu'ils utilisent.

## Ce qui est identique

L'image. Donnez le même scan aux deux et vous obtenez le même résultat.

Ce n'est pas une promesse sur le papier. La version macOS produit une série d'images de
référence, rangées dans le dépôt sous `docs/verification/macos-golden`. Les tests du moteur
Windows les relisent et comparent les valeurs de pixels. Si une modification du moteur
Windows s'écarte du résultat macOS, les tests échouent.

Il en va de même pour :

- La mesure de la base du film et l'inversion
- Toutes les cibles de développement : `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`
- Tonalité, courbes, HSL, étalonnage couleur, virage noir et blanc
- La détection et la réparation GrainMend, y compris le chemin infrarouge
- Les mises en page d'impression et la géométrie des pages
- Le nommage des fichiers exportés, l'écriture EXIF et la politique de métadonnées
- Le format du catalogue, si bien qu'une photothèque créée d'un côté se lit de l'autre

## Ce qui diffère

### Gestion des couleurs

macOS utilise ColorSync, Windows utilise ICM. Les deux acceptent les mêmes profils ICC et
donnent les mêmes valeurs à l'arrondi près. C'est la partie la plus susceptible de dériver
sans bruit, donc les tests de référence la surveillent.

### Graphismes

macOS fait tourner la chaîne de développement sur Core Image. Windows la fait tourner sur
des compute shaders Direct3D, avec un repli CPU sur les machines où le GPU n'est pas
disponible.

La vitesse dépend de la machine plus que de la plateforme. Un Mac Apple Silicon comme un PC
avec un GPU dédié traitent un scan 35 mm sans attente.

### Où vont les fichiers

| | macOS | Windows |
|---|---|---|
| Application | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Photothèque et réglages | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| Journaux | Console et dossier de support | `%LOCALAPPDATA%\Negaflow\Logs` |

### Installation et désinstallation

macOS livre un PKG qui met l'application dans `/Applications`. Pour la retirer, glissez-la
à la corbeille, comme n'importe quelle application Mac.

Windows livre un installateur qui écrit dans votre dossier utilisateur sans demander de
droits administrateur. La désinstallation passe par `Désinstaller negaflow` dans le menu
Démarrer ou par les Paramètres, et retire le dossier de l'application, l'entrée du menu
Démarrer et l'enregistrement du paquet.

### Ligne de commande

macOS livre `negaflow`, une CLI complète qui détecte les scanners, développe des fichiers,
lance GrainMend et mesure les performances. Elle est faite pour être utilisée.

Windows livre `negaflow-cli.exe`, un outil plus petit pour observer ce que le moteur fait
d'un fichier. Il prend des indicateurs plutôt que des sous-commandes et sert au diagnostic,
pas au travail quotidien.

### Signature

Aucune des deux versions n'est signée par un certificat de développeur payant, donc les deux
systèmes préviennent au premier lancement. macOS demande Ouvrir quand même dans
Confidentialité et sécurité. Windows demande Informations complémentaires, puis Exécuter
quand même, après l'avertissement SmartScreen.

## Scanners

Le module scanner est un projet GPL distinct,
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), et il existe
aussi pour les deux systèmes. Il tourne dans son propre processus et communique en JSON, si
bien que negaflow ne contient de code SANE sur aucune des deux plateformes.

Sous Windows, le module passe par le chemin de pilote scanner que Windows fournit déjà.
Rien n'est remplacé, donc VueScan et SilverFast continuent de fonctionner sur la même machine.

## Comment les deux restent alignés

Chaque fonction arrive d'abord sur macOS, puis sur Windows en se réglant sur le comportement
macOS plutôt que sur une spécification écrite. Là où la sortie se mesure, ce sont les images
de référence macOS qui décident si le côté Windows a raison.

Quand les deux divergent, macOS a raison et Windows a un bug.
