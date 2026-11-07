<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, conçu nativement pour Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="version 1.2.6"></a>
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

## Prérequis

Pour l'exécuter :

- Windows 11 24H2 (build 26100) ou ultérieur, 64 bits
- 8 Go de mémoire, 16 Go recommandés en moyen format

Pour le compiler :

- Visual Studio 2026 avec la charge de travail Développement Desktop en C++ (les composants sont listés dans `.vsconfig`)
- Windows 11 SDK 10.0.26100 ou ultérieur
- SDK .NET 10 (`global.json` fixe la version 10.0.302)
- CMake 4.2 ou ultérieur (requis par le générateur `Visual Studio 18 2026`)
- Python 3, pour les scripts d'icône et de ressources

Le build propose aussi des préréglages Arm64. Les versions publiées ne contiennent que du x64.

## Installation

Téléchargez `negaflow-1.2.6-win-x64.exe` depuis [Releases](https://github.com/habinsong/negaflow/releases) et lancez-le. Par défaut, il s'installe dans `%LOCALAPPDATA%\Negaflow\App` sans demander de droits administrateur.

[negaflow-1.2.6-win-x64-setup.zip](https://github.com/habinsong/negaflow/releases/download/v1.2.6/negaflow-1.2.6-win-x64-setup.zip) contient le même programme d'installation, avec les instructions, les mentions légales et les sommes de contrôle SHA-256. Extrayez tous les fichiers avant de lancer le programme d'installation. C'est une archive d'installation, pas une application portable.

Le programme d'installation n'est pas signé. SmartScreen avertit une fois au premier lancement : cliquez sur Informations complémentaires, puis exécutez-le.

Pour désinstaller, utilisez `Uninstall negaflow` dans le menu Démarrer ou la liste des applications dans Paramètres. La bibliothèque et les photos ne sont pas touchées.

Au lancement, l'app demande une fois à GitHub la dernière publication. Si une version plus récente existe, le bas du menu ⋯ en haut à droite affiche « Mettre à jour vers la version X.Y.Z ». Ce choix ouvre la page de publication et enregistre dans Téléchargements le programme d'installation `win-x64.exe`, vérifié avec le `SHA256SUMS.txt` de la publication. L'installation reste à faire vous-même. Quand l'app est à jour, l'élément indique « Vous avez la dernière version. » et ouvre la page du projet. Si la vérification échoue, hors ligne par exemple, l'élément n'apparaît pas.

## Compilation

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Compiler le moteur C++
.\scripts\build.ps1 -Preset x64-release

# Compiler l'application et la lancer
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` accepte `x64-debug`, `x64-release`, `arm64-debug` et `arm64-release`.

Pendant le développement, lancez l'application uniquement avec `run-app.ps1`. Elle est construite comme un paquet MSIX, donc exécuter l'exe du dossier de build ne fait rien. Le script construit le paquet, l'enregistre pour l'utilisateur courant et le démarre par son identifiant d'application.

Pour compiler le programme d'installation :

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

Le résultat est dans `out\release\win-x64`.

## Vérifications

```powershell
# Tests du moteur C++
ctest --preset x64-release --output-on-failure

# Tests de l'application et du catalogue
.\scripts\test-managed.ps1

# Tests de la frontière moteur/application
.\scripts\test-interop.ps1

# Tout cela d'un coup
.\scripts\local-ci.ps1
```

Lancez `scripts\verify-installer.ps1` (appelé aussi par `local-ci.ps1`) dans une session de bureau ouverte. Dans une session SSH, l'enregistrement AppX peut échouer avec `0x80070005` ; le script s'arrête alors avant de toucher à l'installation existante.

La CI n'exécute que les tests autonomes du moteur. Les fichiers de référence macOS restent hors de Git. Pour lancer ces comparaisons, indiquez le dossier de référence dans `NEGAFLOW_MACOS_GOLDEN_ROOT` lors de la configuration de CMake. Il doit contenir `task6-metadata-policy`, `task9-bw-slide`, `task7-coreimage-filters`, `task8-digital-film-look` et `vibrance`. Un fichier manquant ou illisible fait échouer les comparaisons choisies. `ctest --preset x64-release -L external-golden` les exécute, et les tests unitaires ordinaires restent actifs.

## Cibles de couleur personnalisées

CS suit MAIN, HS, SP, F135 et HR dans les pastilles de cibles. Le choisir ouvre en bas à gauche une liste sur deux colonnes de 18 cibles Custom, en groupes de 11, 4 et 3 ; le sélecteur de rendu reste à droite. En entrant dans CS, Emulsion est sélectionnée, et une photo qui utilise déjà une cible Custom la garde.

Custom utilise les mêmes coefficients custom-3 et les mêmes identifiants texte que macOS. La cible choisie est enregistrée dans les réglages de la photo et dans le catalogue, et l'aperçu comme l'export passent par la même étape. L'en-tête de dossier applique la cible choisie au dossier avec le bouton Appliquer existant.

## Vérifier le moteur en ligne de commande

`negaflow-cli.exe` fait tourner le moteur sur un seul fichier. Il prend des options, pas des sous-commandes.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Informations de build
& $cli --build-info

# Contenu d'un fichier de numérisation
& $cli --probe-tiff scan.tif

# Développer et enregistrer en TIFF 16 bits
& $cli --export-developed-tiff16 scan.tif out.tif

# Répartition du temps dans un passage de développement
& $cli --develop-timing scan.tif

# Base du film mesurée automatiquement et valeur retenue
& $cli --auto-base-probe scan.tif
```

Lancez-le sans argument pour la liste complète.

## Scanners

Les commandes de scanner restent masquées tant qu'aucun module n'est installé. Les appareils SANE sont pris en charge par [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), à installer séparément.

Le module parle au scanner par les chemins de pilotes que Windows fournit déjà. VueScan ou SilverFast peuvent rester installés sur la même machine.

## En cas de problème

L'application écrit des journaux texte dans `%LOCALAPPDATA%\Negaflow\Logs`.

| Fichier | Ce qu'il enregistre |
|---|---|
| `export-trace.txt` | Export et exportation rapide, échecs compris |
| `termination.txt` | Ce qui s'est passé pendant la fermeture de l'application |
| `settings-change.txt` | Réglages modifiés et ce qui les a modifiés |

Ces trois-là sont toujours actifs. Deux autres sont désactivés par défaut :

- `preview-trace.txt` : créez un fichier vide nommé `preview-trace.on` dans le même dossier.
- `stage-trace.txt` : définissez la variable d'environnement `NEGAFLOW_STAGE_TRACE=1` avant de lancer l'application. Il enregistre des statistiques de pixels à chaque étape du développement.

## Arborescence

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, décodage et export (C++)
│   ├── Interop/       La couche entre moteur et application (C#)
│   ├── Catalog.Core/  Stockage de la bibliothèque (C#)
│   ├── Shell.Core/    Logique de développement, de tirage et d'export (C#)
│   ├── Shell/         Écrans Bibliothèque, Développement et Tirage (WinUI 3)
│   └── Cli/           Outil d'inspection du moteur (C++)
├── scripts/           Scripts de build, de test et de packaging
├── tests/             Tests du moteur, de l'application et de la frontière
└── Installer/windows/ Programme d'installation NSIS
```

## Documents liés

- [Ce qui diffère entre les deux versions](../../docs/fr/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/fr/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/fr/product/GRAINMEND.md)
- [Architecture produit](../../docs/fr/architecture/PRODUCT_ARCHITECTURE.md)
