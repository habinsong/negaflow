<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, conçu nativement pour macOS.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="version 1.1.1"></a>
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

## Ce qu'il faut

Pour l'exécuter :

- macOS 14.0 ou ultérieur
- Apple Silicon ou Intel
- 8 Go de mémoire pour du 35 mm, 16 Go plus confortables en moyen format

Pour le compiler :

- Xcode 26 pour l'application
- Swift 5.9 ou ultérieur pour le moteur et la CLI

## Installation

Téléchargez depuis [Releases](https://github.com/habinsong/negaflow/releases).

| Fichier | Mac pris en charge |
|---|---|
| `negaflow-1.1.1-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.1.1-mac-arm64.pkg` | Apple Silicon uniquement |

Le PKG Universal convient à la plupart. Il installe dans `/Applications`. Pour déplacer l'application vous-même, prenez le DMG ou le ZIP de la même page.

L'application n'est pas notariée, macOS la bloque donc au premier lancement. Autorisez-la dans Réglages Système, sous Confidentialité et sécurité, avec Ouvrir quand même.

La photothèque et les réglages sont dans `~/Library/Application Support/negaflow`.

## Compilation

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Compiler en Release puis lancer
bash scripts/run-app.sh

# Compiler sans lancer
bash scripts/run-app.sh build
```

`run-app.sh` appelle `xcodebuild`, assemble le paquet et le signe localement. Pour le moteur ou la CLI seuls, `swift build` suffit.

Pour produire les fichiers de distribution :

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## Vérifications

```bash
# Tests Swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Compilation Release de l'application
bash scripts/run-app.sh build

# Vérification complète du dépôt
bash scripts/ci-gate.sh
```

## Ligne de commande

La version macOS embarque une CLI.

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

# Liste des profils et autotest du moteur
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

Lancez `negaflow` sans argument pour la liste complète des options.

## Scanners

Les commandes du scanner n'apparaissent pas tant qu'un module n'est pas installé. Les appareils SANE passent par [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), qui s'installe à part.

## Modules

| Module | Rôle |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, profils et export |
| `ScannerKit` | Vérification des capacités scanner et connexion des modules |
| `negaflowApp` | Écrans photothèque, développement, numérisation et export |
| `negaflowCLI` | Commandes de développement, numérisation, benchmark et autotest |

## Images de référence

`docs/verification/macos-golden`, à la racine du dépôt, contient les images rendues par cette compilation. Les tests du moteur Windows les lisent et comparent pixel par pixel. Ne les régénérez que lorsque la sortie macOS doit changer.

## Documents liés

- [Différences entre macOS et Windows](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
