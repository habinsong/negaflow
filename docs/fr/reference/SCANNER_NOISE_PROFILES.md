# Profils de bruit des scanners

[Accueil de la documentation](../README.md)

On ne peut pas bâtir un profil de bruit à partir d'une seule photo ordinaire, car sa partie haute fréquence mélange le sujet et le grain du film.

Numérisez au moins trois fois, avec les mêmes réglages, une cible uniforme ou en gradins. La variation de la valeur d'un pixel à la même position donne la variance par niveau de signal.

- [ISO 15739:2023](https://www.iso.org/standard/82233.html) définit comment mesurer et rapporter le bruit par signal pour les appareils d'imagerie numérique.
- [ISO 21550:2004](https://www.iso.org/standard/35939.html) définit comment mesurer la plage dynamique des scanners par transmission et par réflexion.

L'ISO 15739 est écrite pour les appareils photo numériques. negaflow ne prétend pas que les scanners en relèvent et n'emprunte que l'idée de la mesure répétée et de la variance par signal.

> [!NOTE]
> Le lot fourni ne contient aucun profil de bruit d'appareil `holdoutValidated`, donc aucun ne s'applique automatiquement. Les valeurs de texture des profils existants ne servent pas de données de bruit de capteur.

## Ce que couvre un profil

`ScannerNoiseProfile` ne correspond que si tous ces éléments sont identiques :

- Fabricant et modèle du scanner
- Résolution en DPI
- Profondeur de bits par canal
- Mode couleur
- Multi-exposition activée ou non

Les valeurs d'un modèle voisin ou d'une autre résolution ne sont pas empruntées. Si plusieurs profils automatiques correspondent exactement, le résultat est un échec, pas un choix arbitraire.

À partir d'au moins trois numérisations RVB linéaires de la même scène, on ajuste par canal :

```math
\operatorname{variance}(x) = m_{\mathrm{shot}}x + b_{\mathrm{read}}
```

Le profil enregistre aussi :

- Le SHA-256 du matériel d'étalonnage
- Le nombre d'images et d'échantillons mesurés
- La plage de signal observée
- Le R² de la régression
- L'intensité de réduction du bruit validée

L'intensité maximale du code protège seulement contre un calcul défaillant. Ce n'est pas un seuil de qualité.

## États

| État | Signification | Application automatique |
|---|---|---|
| `draft` | Mesure ou réglage inachevé | Non |
| `measured` | Mesures répétées sur un vrai appareil, sans validation indépendante | Non |
| `holdoutValidated` | Intensité vérifiée sur un matériel de validation distinct | Seulement en cas de correspondance exacte |

L'usage automatique exige exactement un profil `holdoutValidated` correspondant, et les SHA-256 du matériel d'étalonnage et de validation ainsi que les contrôles de structure du fichier doivent passer. `draft` et `measured` ne peuvent pas modifier les réglages généraux existants.

## Où en est-on

Les profils couleur NORITSU et SP-3000 du dépôt portent des valeurs `texture` issues de scènes réelles. Elles mélangent sujet, mise au point et grain du film : elles ne servent pas de données de bruit de capteur.

Il n'existe pas encore de cibles uniformes répétées ni de matériel de validation distinct. Aucun profil de bruit d'appareil validé n'est fourni, et le chemin automatique utilise les réglages généraux existants.

Un vrai profil demande tout ceci :

1. Trois numérisations linéaires ou plus, avec le même appareil, la même résolution, la même profondeur, le même mode couleur et le même réglage de multi-exposition
2. La liste des fichiers et le SHA-256 du matériel d'étalonnage
3. Une scène de validation non utilisée pour l'étalonnage, avec son SHA-256
4. Une comparaison entre réduction du bruit et conservation du détail et du grain
5. Un contrôle à 100 % par un vrai utilisateur

La capture sur du matériel réel relève du module `negaflow-scanner-sane`. Les options SANE et le code de contrôle des appareils n'entrent pas dans ce dépôt.
