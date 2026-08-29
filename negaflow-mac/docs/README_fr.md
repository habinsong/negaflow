<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, développé nativement pour macOS.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="version 1.1.0"></a>
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

Pour l'utiliser :

- macOS 14.0 ou plus récent
- Apple Silicon ou Intel
- 8 Go de mémoire pour du 35 mm, 16 Go plus confortables en moyen format

Pour le compiler :

- Xcode 26 pour l'application
- Swift 5.9 ou plus récent pour le moteur et la CLI

## Installation

Téléchargez depuis [Releases](https://github.com/habinsong/negaflow/releases).

| Téléchargement | Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon et Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Apple Silicon uniquement |

La plupart des gens prendront le PKG Universal. Ouvrez-le, suivez l'installateur, et
l'application arrive dans `/Applications`. Un DMG et un ZIP sont sur la même page si vous
préférez déplacer l'application vous-même.

L'application n'est pas notarisée. Au premier lancement macOS la bloque, et vous
l'autorisez dans Réglages Système, sous Confidentialité et sécurité, en cliquant sur
Ouvrir quand même.

Votre photothèque et vos réglages vivent dans `~/Library/Application Support/negaflow`.

## Compilation

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Compiler en Release et lancer
bash scripts/run-app.sh

# Compiler sans lancer
bash scripts/run-app.sh build
```

`run-app.sh` appelle `xcodebuild`, assemble le bundle et signe en local. Pour travailler
seulement sur le moteur ou la CLI, `swift build` suffit et évite Xcode.

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

# Contrôle complet du dépôt
bash scripts/ci-gate.sh
```

## Ligne de commande

La version macOS livre une CLI complète à côté de l'application.

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

Les contrôles scanner restent cachés tant qu'aucun module n'est installé.
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) couvre les
appareils SANE et s'installe séparément.

## Modules

| Module | Rôle |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, profils, export |
| `ScannerKit` | Vérification des capacités scanner et lien avec le module |
| `negaflowApp` | Écrans photothèque, développement, scan et export |
| `negaflowCLI` | Commandes de développement, scan, mesure et autotest |

## Images de référence

`docs/verification/macos-golden`, à la racine du dépôt, contient les images rendues par
cette version. Les tests du moteur Windows les lisent et comparent pixel par pixel : c'est
ainsi que les deux versions restent d'accord. Ne les régénérez que si la sortie macOS doit
changer.

## Documents liés

- [Ce qui diffère entre les deux](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
