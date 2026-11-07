<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, conçu nativement pour macOS.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="version 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou ultérieur"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <strong>Français</strong> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README_fr.md">Documentation commune</a> ·
  <a href="../../negaflow-windows/docs/README_fr.md">Windows</a>
</p>

---

## Prérequis

Pour l'exécuter :

- macOS 14.0 ou ultérieur (macOS 14, 26 et 27 sont pris en charge)
- Apple Silicon ou Intel
- 8 Go de mémoire, 16 Go recommandés en moyen format

Pour le compiler :

- Xcode 26 ou ultérieur pour l'application
- Swift 5.9 ou ultérieur pour le moteur et la CLI

## Installation

Téléchargez depuis [Releases](https://github.com/habinsong/negaflow/releases).

| Fichier | Mac pris en charge |
|---|---|
| `negaflow-1.2.6-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.2.6-mac-arm64.pkg` | Apple Silicon uniquement |

Le PKG Universal convient à la plupart des Mac et s'installe dans `/Applications`. La même page propose un DMG et un ZIP pour placer l'application vous-même.

L'application est signée en ad hoc et n'est pas notariée, donc macOS bloque le premier lancement. Autorisez-la dans Réglages Système, Confidentialité et sécurité, avec Ouvrir quand même.

La bibliothèque et les réglages sont dans `~/Library/Application Support/negaflow`.

Au lancement, l'app demande une fois à GitHub la dernière publication. Si une version plus récente existe, le bas du menu ⋯ en haut à droite affiche « Mettre à jour vers la version X.Y.Z ». Ce choix ouvre la page de publication et enregistre dans Téléchargements le PKG adapté à ce Mac, vérifié avec le `SHA256SUMS.txt` de la publication. L'installation reste à faire vous-même. Quand l'app est à jour, l'élément indique « Vous avez la dernière version. » et ouvre la page du projet. Si la vérification échoue, hors ligne par exemple, l'élément n'apparaît pas.

## Compilation

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Compiler une app Release et la lancer
bash scripts/run-app.sh

# Compiler sans lancer
bash scripts/run-app.sh build
```

`run-app.sh` appelle `xcodebuild`, assemble le bundle de l'application et le signe localement. Pour le moteur ou la CLI seuls, `swift build` suffit.

Artefacts de publication :

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## Vérifications

```bash
# Tests Swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Build Release de l'application
bash scripts/run-app.sh build

# Toutes les vérifications du dépôt
bash scripts/ci-gate.sh
```

## Cibles de couleur personnalisées

CS suit MAIN, HS, SP, F135 et HR dans les pastilles de cibles. Le choisir ouvre, dans le sélecteur en bas à gauche, une liste sur deux colonnes de 18 cibles Custom ; le sélecteur de rendu reste à droite. En entrant dans CS, Emulsion est sélectionnée, et une image qui utilise déjà une cible Custom la garde.

La liste a trois groupes : d'Emulsion à Dichroic (11), de Wetzlar à Rochester (4), de Slide Show à Point & Shoot (3). Les cibles Custom appliquent la réponse custom-3 en tonalité, densité et chroma. L'enregistrement, les aperçus, les vignettes et l'export utilisent l'identifiant de la cible choisie. Les autres cibles ne changent pas.

La CLI accepte les mêmes identifiants : `--target classic`, `--target dye-transfer`, `--target point-and-shoot`.

## Ligne de commande

La version macOS fournit une CLI.

```bash
swift build

# Trouver les scanners
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# Développer
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# Profils et autotest du moteur
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

Lancez `negaflow` sans argument pour la liste complète des options.

## Scanners

Les commandes de scanner restent masquées tant qu'aucun module n'est installé. Les appareils SANE sont pris en charge par [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), à installer séparément.

## Modules

| Module | Rôle |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, profils, export |
| `ScannerKit` | Vérification des capacités du scanner et connexion des modules |
| `negaflowApp` | Écrans Bibliothèque, Développement, Numérisation et Exportation |
| `negaflowCLI` | Commandes de développement, de numérisation, de benchmark et d'autotest |

## Images de référence

`docs/verification/macos-golden` contient des images rendues par ce build. Git ignore ce dossier : il n'existe que sur la machine qui les a rendues. Les tests du moteur Windows en comparent des copies pixel par pixel. Ne les régénérez que si la sortie macOS doit changer.

## Documents liés

- [Ce qui diffère entre les deux versions](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
