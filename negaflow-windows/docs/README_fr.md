<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, conçu nativement pour Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="version 1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 ou plus récent"></a>
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
  <a href="../../negaflow-mac/docs/README_fr.md">macOS</a>
</p>

---

## Ce qu'il faut

Pour l'exécuter :

- Windows 11 24H2 (build 26100) ou plus récent, 64 bits
- 8 Go de mémoire pour du 35 mm, 16 Go plus confortables en moyen format

Pour le compiler :

- Visual Studio 2022 avec la charge de travail Développement Desktop en C++
- SDK Windows 11 (10.0.26100 ou plus récent)
- SDK .NET 10
- CMake 3.28 ou plus récent
- Python 3.11 ou plus récent, pour les scripts d'icônes et de ressources

Cela tourne aussi sur les machines Arm64. Les versions Arm64 sont moins vérifiées que les x64.

## Installation

Téléchargez `negaflow-1.1.1-win-x64.exe` depuis [Releases](https://github.com/habinsong/negaflow/releases) et lancez-le.

Aucun droit administrateur nécessaire. SmartScreen prévient une fois au premier lancement : cliquez sur Informations complémentaires, puis exécutez.

La désinstallation passe par `Désinstaller negaflow` dans le menu Démarrer, ou par la liste des applications dans Paramètres. La photothèque et les photos restent intactes.

## Compilation

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Compiler le moteur C++
.\scripts\build.ps1 -Preset x64-release

# Compiler l'application puis la lancer
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` accepte `x64-debug`, `x64-release`, `arm64-debug` et `arm64-release`.

`run-app.ps1` est le seul moyen de lancer l'application pendant le développement. L'application est compilée en paquet MSIX, donc lancer l'exe du dossier de build ne donne rien. Le script fabrique le paquet, l'enregistre pour l'utilisateur courant, puis le lance par son identifiant.

Pour fabriquer l'installateur :

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

Le résultat arrive dans `out\release\win-x64`.

## Vérifications

```powershell
# Tests du moteur C++
ctest --preset x64-release --output-on-failure

# Tests de l'application et du catalogue
.\scripts\test-managed.ps1

# Tests de la frontière moteur/application
.\scripts\test-interop.ps1

# Tout cela en une fois
.\scripts\local-ci.ps1
```

Les tests du moteur comprennent une comparaison aux images de référence. Ils lisent les fichiers produits par la version macOS et vérifient que le moteur Windows sort les mêmes pixels.

## Vérifier le moteur en ligne de commande

`negaflow-cli.exe` montre comment le moteur traite un fichier. Il prend des drapeaux plutôt que des sous-commandes.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Voir de quelle compilation il s'agit
& $cli --build-info

# Voir ce que contient un fichier de numérisation
& $cli --probe-tiff scan.tif

# Développer et enregistrer en TIFF 16 bits
& $cli --export-developed-tiff16 scan.tif out.tif

# Voir où passe le temps sur une passe de développement
& $cli --develop-timing scan.tif

# Chercher la base du film automatiquement et voir ce qui a été retenu
& $cli --auto-base-probe scan.tif
```

Lancez-le sans argument pour la liste complète.

## Scanners

Les commandes du scanner n'apparaissent pas tant qu'un module n'est pas installé. Les appareils SANE passent par [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), qui s'installe à part.

Le module dialogue avec le scanner par les chemins de pilotes que Windows fournit déjà. Vous pouvez continuer à utiliser VueScan ou SilverFast sur la même machine.

## En cas de problème

L'application écrit des journaux texte dans `%LOCALAPPDATA%\Negaflow\Logs`.

| Fichier | Ce qui est consigné |
|---|---|
| `export-trace.txt` | Export et export rapide, échecs compris |
| `termination.txt` | Ce qui s'est passé pendant la fermeture |
| `settings-change.txt` | Réglages modifiés et par quoi |

Ces trois-là sont toujours actifs. Deux autres ne s'activent que pour creuser un problème précis.

- `preview-trace.txt`. Créez un fichier vide nommé `preview-trace.on` dans le même dossier pour l'activer.
- `stage-trace.txt`. Définissez la variable d'environnement `NEGAFLOW_STAGE_TRACE=1` avant de lancer l'application. Il consigne les statistiques de pixels à chaque étape du développement.

## Composition des dossiers

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, décodage et export (C++)
│   ├── Interop/       Couche entre le moteur et l'application (C#)
│   ├── Catalog.Core/  Stockage de la photothèque (C#)
│   ├── Shell.Core/    Logique de développement, impression et export (C#)
│   ├── Shell/         Écrans photothèque, développement et impression (WinUI 3)
│   └── Cli/           Outil de vérification du moteur (C++)
├── scripts/           Scripts de compilation, de test et de paquet
├── tests/             Tests moteur, application et frontière
└── Installer/windows/ Installateur NSIS
```

## Documents liés

- [Différences entre macOS et Windows](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
