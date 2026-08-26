# Profils de bruit des scanners

[Accueil de la documentation](../README.md)

On ne fabrique pas un profil de bruit à partir d'une seule photographie ordinaire.
Dans une photographie, le contenu haute fréquence mêle le sujet et le grain du film.

Numérisez une mire plate ou à échelons au moins trois fois avec les mêmes réglages.
La façon dont bouge le pixel au même endroit donne la variance par niveau de signal.

- [ISO 15739:2023](https://www.iso.org/standard/82233.html) fixe la mesure et la présentation du
bruit par signal pour les appareils d'imagerie numérique.
- [ISO 21550:2004](https://www.iso.org/standard/35939.html) fixe la mesure de la plage dynamique
des scanners à transmission et à réflexion.

L'ISO 15739 est écrite pour les appareils photo numériques. negaflow ne prétend pas que les scanners
relèvent de la même norme.
Seules les idées de mesure répétée et de variance par signal sont reprises.

> [!NOTE]
> Le lot actuel ne contient aucun profil de bruit `holdoutValidated`, donc aucun ne s'applique
> automatiquement. Les valeurs de texture des profils existants ne servent pas de données de
> bruit de capteur.

## Ce qu'un profil couvre

`ScannerNoiseProfile` ne compte comme correspondance que si tout ceci est identique.

- Fabricant et modèle du scanner
- Résolution en DPI
- Profondeur de bits par canal
- Mode couleur
- Multi-exposition activée ou non

Les valeurs d'un modèle voisin ou d'une autre résolution ne sont pas empruntées.
Si plusieurs profils automatiques correspondent exactement, l'opération échoue au lieu d'en choisir
un.

À partir d'au moins trois numérisations RVB linéaires de la même scène, on ajuste ceci par canal.

```math
\operatorname{variance}(x) = m_{\mathrm{shot}}x + b_{\mathrm{read}}
```

Ce qui est noté avec le profil :

- SHA-256 du matériel de calibration
- Nombre d'images mesurées et d'échantillons
- La plage de signal observée
- R² de la régression
- L'intensité de réduction du bruit validée

L'intensité maximale du code sert seulement de garde-fou contre un calcul aberrant.
Ce n'est pas un seuil de qualité.

## États

| État | Signification | Application automatique |
|---|---|---|
| `draft` | Mesure ou réglage inachevé | Non |
| `measured` | Mesures répétées sur un appareil réel, sans validation indépendante | Non |
| `holdoutValidated` | Intensité vérifiée sur un matériel de validation distinct | Seulement en correspondance exacte |

L'usage automatique demande exactement un profil `holdoutValidated` correspondant.
Les SHA-256 des matériels de calibration et de validation, ainsi que les contrôles de structure de
fichier, doivent passer aussi.
`draft` et `measured` ne peuvent pas modifier les réglages généraux existants.

## Où on en est

Les profils colorimétriques NORITSU et SP-3000 du dépôt portent des valeurs `texture` issues de
scènes réelles.
Ces valeurs mêlent sujet, mise au point et grain du film : elles ne servent pas comme données de
bruit de capteur.

Les mires plates répétées et un matériel de validation distinct n'existent pas encore.
Aucun profil de bruit validé n'est fourni, et le chemin automatique utilise les réglages généraux
existants.

Ajouter un vrai profil demande tout ceci.

1. Au moins trois numérisations linéaires avec le même appareil, la même résolution, la même profondeur de bits, le même mode couleur et le même réglage de multi-exposition
2. La liste des fichiers et les SHA-256 du matériel de calibration
3. Une scène de validation non utilisée pour la calibration, avec son SHA-256
4. Une comparaison de la réduction du bruit avec la préservation du détail et du grain
5. Une vérification à 100 % par un utilisateur réel

La capture sur matériel réel revient au plugin `negaflow-scanner-sane`.
Les options SANE et le code de contrôle des périphériques n'entrent pas dans ce dépôt.
