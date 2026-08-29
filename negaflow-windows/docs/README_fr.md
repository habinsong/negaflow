<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, développé nativement pour Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="version 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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

Pour l'utiliser :

- Windows 11 (build 26100 ou plus récent), 64 bits
- 8 Go de mémoire pour du 35 mm, 16 Go plus confortables en moyen format

Pour le compiler :

- Visual Studio 2022 avec la charge de travail Développement Desktop en C++
- SDK Windows 11 (10.0.26100 ou plus récent)
- SDK .NET 10
- CMake 3.28 ou plus récent
- Python 3.11 ou plus récent, pour les scripts d'icônes et de ressources

L'application tourne aussi sur les machines Arm64, mais ces versions sont moins éprouvées
que les versions x64.

## Installation

Téléchargez `negaflow-1.1.0-x64-setup.exe` depuis
[Releases](https://github.com/habinsong/negaflow/releases) et lancez-le.

Aucun droit administrateur n'est nécessaire. SmartScreen prévient au premier lancement :
cliquez sur Informations complémentaires, puis Exécuter quand même.

Pour désinstaller, prenez `Désinstaller negaflow` dans le menu Démarrer, ou cherchez
negaflow dans les Paramètres. Votre photothèque et vos photos ne sont pas touchées.

## Compilation

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Compiler le moteur C++
.\scripts\build.ps1 -Preset x64-release

# Compiler l'application et la lancer
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` accepte `x64-debug`, `x64-release`, `arm64-debug` ou `arm64-release`.

Pendant le développement, `run-app.ps1` est le seul moyen de lancer l'application. Elle est
construite comme un paquet MSIX, donc l'exécutable du dossier de build ne démarre pas tout
seul. Le script empaquette, enregistre pour votre compte, puis lance par identifiant
d'application. C'est le même chemin que l'installateur, sans l'installation.

Pour construire l'installateur :

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

# Tests de la frontière moteur / application
.\scripts\test-interop.ps1

# Tout ce qui précède d'un coup
.\scripts\local-ci.ps1
```

Les tests du moteur comprennent des comparaisons d'images de référence. Ils lisent des
fichiers produits par la version macOS et vérifient que le moteur Windows sort les mêmes
pixels.

## Vérifier le moteur en ligne de commande

`negaflow-cli.exe` est un petit outil pour observer ce que le moteur fait d'un fichier. Il
sert à contrôler un comportement, pas au travail quotidien, donc il prend des indicateurs
plutôt que des sous-commandes.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# De quel build il s'agit
& $cli --build-info

# Lire un scan et dire ce que le fichier contient
& $cli --probe-tiff scan.tif

# Développer et écrire un TIFF 16 bits
& $cli --export-developed-tiff16 scan.tif out.tif

# Où passe le temps dans une passe de développement
& $cli --develop-timing scan.tif

# Chercher la base du film automatiquement et dire ce qui a été retenu
& $cli --auto-base-probe scan.tif
```

Lancez-le sans argument pour voir la liste complète.

## Scanners

Les contrôles scanner restent cachés tant qu'aucun module n'est installé.
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) couvre les
appareils SANE sous Windows et s'installe séparément.

Le module passe par le chemin de pilote scanner que Windows fournit déjà, si bien que
VueScan et SilverFast continuent de fonctionner sur la même machine.

## Quand quelque chose cloche

L'application écrit des journaux en texte simple dans `%LOCALAPPDATA%\Negaflow\Logs`.

| Fichier | Ce qu'il note |
|---|---|
| `export-trace.txt` | Chaque export et export rapide, échecs compris |
| `termination.txt` | Ce qui s'est passé pendant la fermeture |
| `settings-change.txt` | Les réglages modifiés et ce qui les a modifiés |

Ces trois-là sont toujours actifs. Quand vous signalez un problème, le bon fichier
l'explique en général.

Deux autres sont inactifs par défaut et servent à creuser un problème précis :

- `preview-trace.txt`, activé en créant un fichier vide nommé `preview-trace.on` dans le
  même dossier
- `stage-trace.txt`, activé en définissant la variable d'environnement
  `NEGAFLOW_STAGE_TRACE=1` avant le lancement. Il note des statistiques de pixels après
  chaque étape d'une passe de développement, ce qui permet de voir où un aperçu et un
  export ont cessé de coïncider.

## Organisation

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, décodage et export (C++)
│   ├── Interop/       Le pont entre le moteur et l'application (C#)
│   ├── Catalog.Core/  Stockage de la photothèque (C#)
│   ├── Shell.Core/    Logique de développement, impression et export (C#)
│   ├── Shell/         Écrans photothèque, développement et impression (WinUI 3)
│   └── Cli/           Outil de vérification du moteur (C++)
├── scripts/           Scripts de compilation, de test et d'empaquetage
├── tests/             Tests du moteur, de l'application et de la frontière
└── Installer/windows/ Installateur NSIS
```

## Documents liés

- [Ce qui diffère entre les deux](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
