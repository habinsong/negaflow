<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="icône de negaflow">
</p>

<h1 align="center">negaflow</h1>

<p align="center">De la pellicule à la photographie finie. Fonctionne nativement sur macOS et Windows.</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/fr/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="site web"></a>
  <a href="#téléchargement"><img src="https://img.shields.io/badge/version-1.1.3-EF8B26" alt="version 1.1.3"></a>
  <a href="negaflow-mac/docs/README_fr.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou ultérieur"></a>
  <a href="negaflow-windows/docs/README_fr.md"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 ou plus récent"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="licence Apache 2.0"></a>
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
  <a href="https://habinsong.github.io/negaflow-site/fr/">Site web</a> ·
  <a href="https://habinsong.github.io/negaflow-site/fr/camera-scanning/">Guide de reproduction au boîtier</a> ·
  <a href="https://habinsong.github.io/negaflow-site/fr/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/fr/develop-dark.webp">
    <img src="docs/images/fr/develop-light.webp" alt="negaflow, vue Développement">
  </picture>
</p>

**negaflow** est une application qui reçoit la pellicule que vous avez numérisée ou reproduite au boîtier, et la développe. Couleur ou noir et blanc, négatif ou positif, tout passe. De la photothèque au développement puis au tirage, tout se termine dans une seule application. Les valeurs de retouche sont enregistrées à part de l'original, donc le fichier d'origine reste tel quel.

Le moteur de développement s'appelle **Chroma Engine**, et la réparation des poussières et rayures s'appelle **GrainMend**. Ce n'est pas grave si vous n'avez pas de scanner. En important seulement des fichiers image, vous pouvez développer et exporter. La connexion au scanner ne s'ouvre qu'une fois un module installé à part.

> Contrairement à la façon dont l'engouement pour l'argentique continue de croître, le processus de la photographie argentique, lui, est à l'arrêt. À moins de tirer la pellicule à la manière argentique, il faut passer par une conversion en numérique pour qu'elle parvienne enfin à nos yeux.
>
> Or tout ce processus est en train de s'arrêter. Les laboratoires et les boutiques de développement disparaissent peu à peu, et le soutien des fabricants et de leurs produits diminue.
>
> Ce projet est né des désagréments ressentis en travaillant d'une manière puis d'une autre, et de l'idée qu'il serait bien qu'une telle fonction existe. En m'appuyant sur l'expérience et les connaissances acquises en utilisant la pellicule 35 mm et le moyen format, j'ai tout développé moi-même de A à Z. Au début c'était un projet-jouet que je bricolais en m'en servant seul, mais aujourd'hui negaflow est devenu quelque chose de plus que cela.
>
> Au fond, ce qui compte avant tout, c'est que ça marche « bien », que ce soit confortable à utiliser, que ce soit rapide, et que le résultat soit fait correctement tout seul. Développé de façon indépendante, **negaflow** fonctionne nativement sur macOS comme sur Windows, et j'y ai fondu à la fois les manières de faire des laboratoires et celles des particuliers.
>
>
> **En hommage, cet été, au bicentenaire de la première photographie de Niépce.** 25 juillet 2026.
## negaflow for macOS and Windows


| | macOS | Windows |
|---|---|---|
| Interface | SwiftUI | WinUI 3 |
| Moteur | Swift + Core Image | C++ + Direct3D |
| Gestion des couleurs | ColorSync | Windows ICM |

Les deux applications sont des applications natives développées dans des langages différents et de manières différentes, et malgré cela les fonctions et les résultats sont identiques.

Le code du moteur se trouve dans le module `Chromabase` sur macOS et dans le module `Native` sur Windows.

Il existe une façon de fabriquer les deux à la fois (le multiplateforme), mais en procédant ainsi les deux deviennent lentes et ne fonctionnent pas correctement. J'ai donc réécrit le code depuis le début, à la manière propre à chaque système. Ce qui est identique et ce qui ne l'est pas est écrit [ici](docs/fr/platform/PLATFORM_DIFFERENCES.md).

## Téléchargement

Il suffit de le prendre sur [GitHub Releases](https://github.com/habinsong/negaflow/releases).

| Fichier | Environnement |
|---|---|
| `negaflow-1.1.3-mac-universal.pkg` | macOS 14 ou ultérieur, Apple Silicon et Intel |
| `negaflow-1.1.3-mac-arm64.pkg` | macOS 14 ou ultérieur, Apple Silicon uniquement |
| `negaflow-1.1.3-win-x64.exe` | Windows 11 24H2 ou plus récent, x64 |

La plupart des Mac se contentent du PKG Universal. Bien sûr, le fichier pour Silicon ainsi qu'un DMG et un ZIP sont aussi déposés sur la même page. Au premier lancement, il faut ouvrir Réglages Système, aller dans Confidentialité et sécurité, et cliquer une fois sur Ouvrir quand même.

L'installation Windows se termine à l'intérieur de votre dossier utilisateur et ne demande pas de droits administrateur. Comme il n'y a pas de signature, SmartScreen bloque une fois. Cliquez sur Informations complémentaires puis exécutez. La désinstallation se fait depuis le Panneau de configuration.

Brancher un vrai scanner demande un module à part, et pour les scanners SANE il y a [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane). Naturellement, cela fonctionne sur macOS comme sur Windows.

## Fonctions
> Tout ce qu'il faut pour transformer la pellicule argentique en photographie finie est là.
- À commencer par mesurer la base du film et développer les négatifs et positifs couleur et noir et blanc
- Tout ce que demande la retouche : exposition, contraste, courbes, TSL, étalonnage
- Des options supplémentaires comme l'accentuation, la réduction de bruit, le grain, le vignetage, la halation
- GrainMend, qui restaure les photos en retirant poussières et rayures.
- Une photothèque avec bobines, dossiers, collections, notes, piles, copies virtuelles, et recherche par boîtier, objectif ou film
- Des préréglages et un copier-coller qui emportent ensemble procédé, cible, tonalité, couleur, détail, recadrage et orientation
- Export JPEG et TIFF 16 bits, profils ICC, et enregistrement dans l'EXIF des notes de boîtier, objectif, film
- Sept mises en page d'impression et aperçus de papier, formats photo et ISO, jusqu'à la fonction C-print.

## Chroma Engine

**Chroma Engine** prend en charge l'inversion et le développement de la pellicule.

Avant de développer un négatif, il mesure d'abord la base du film. Il lit la valeur dans une zone que la lumière n'a jamais atteinte. Là où la mesure automatique est décalée, il suffit de piquer à la pipette ou d'ajuster les valeurs RVB.

La valeur par défaut est `MAIN` avec des corrections manuelles. Tonalité auto, balance des blancs auto, niveaux auto et couleur auto ne s'exécutent que lorsqu'on appuie dessus.

Les autres cibles sont celles-ci. `PRINT` qui sort par un profil ICC d'imprimante, `HS` et `SP` de la famille minilab, `F135` et `HR` de la famille des équipements de laboratoire, `EXPIRED` qui tente de rattraper les vieux films. Pour la sortie, on choisit entre sRGB, Display P3, Adobe RGB, et un profil ICC RVB à soi.

L'ordre de l'inversion et du traitement des couleurs est dans la [documentation Chroma Engine](docs/fr/product/CHROMA_ENGINE.md).

## GrainMend

> **GrainMend** répare poussières, micro-trous, rayures et dégâts d'émulsion.

**GrainMend RGB** est une approche logicielle, elle diffère donc de l'IR matériel. <br> <br>
`Automatique` balaie toute la photo. Simple, mais il y aura des fausses détections. <br>
`Guidé` ne regarde que la zone indiquée. C'est sur la poussière ramassée pendant la numérisation qu'il agit le mieux. <br>
`Pinceau` est l'outil pour peindre soi-même les endroits qu'Automatique a manqués, et le tampon de clonage déplace tels quels les pixels d'une position choisie.<br>
`Tampon de clonage` est une fonction de tampon où l'on choisit la texture voulue et où l'on peint soi-même. <br>

Automatique et Guidé comblent les défauts en regardant la texture alentour. Avant de combler, ils regardent d'abord la direction et la structure environnante. Prendre une rambarde ou un joint de carrelage dans la photo pour une rayure et l'effacer, ce n'est pas une réparation mais un dégât.

Le résultat des corrections reste sous forme de calques. On peut changer l'intensité, vérifier le masque, en désactiver ou en supprimer un par un.<br>
**GrainMend IR** ajoute au même relevé les résultats de détection du canal infrarouge transmis par un module scanner.



**GrainMend IR** utilise le canal infrarouge (IR) du scanner, mais il n'est ni une implémentation ni un mode de compatibilité de Digital ICE, iSRD ou SRDx. Le fonctionnement ainsi que les critères de qualité et de performance sont réunis dans la [documentation GrainMend](docs/fr/product/GRAINMEND.md).

## De l'import à l'impression

1. Importez des fichiers image, ou numérisez avec un module installé.
2. Choisissez le type de procédé de développement et indiquez la cible de numérisation.
3. Ajustez la couleur et la tonalité dans Chroma Engine.
4. Appliquez GrainMend aux photos qui en ont besoin.
5. Vérifiez avec la vue avant/après et l'histogramme, puis imprimez ou exportez.

Importer seulement ne développe rien. Cela démarre quand vous choisissez un procédé et une cible pour un dossier et appuyez sur **Appliquer**, ou quand vous entrez dans la vue Développement. Il existe aussi un réglage à part pour que cela se fasse automatiquement, et sa valeur par défaut est désactivée.

Ce que chaque action fait à vos fichiers d'origine est réuni sous forme de tableau dans [De la photothèque à l'impression](docs/fr/product/WORKFLOW.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/fr/library-dark.webp">
    <img src="docs/images/fr/library-light.webp" alt="negaflow, vue Photothèque">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/fr/print-dark.webp">
    <img src="docs/images/fr/print-light.webp" alt="negaflow, vue Impression">
  </picture>
</p>

## Scanners et profils de film

negaflow lui-même n'ouvre pas de fonctions d'après le nom de modèle d'un scanner.<br> Il n'utilise que la résolution, la profondeur, la zone de numérisation, l'exposition et le support IR que le module déclare. Si l'on devine d'après le nom, des fonctions absentes de l'appareil s'allument.

Les appareils SANE sont pris en charge par [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), un projet GPL séparé. Le module tourne dans son propre processus et le format d'échange est JSON. **negaflow** ne contient aucun code SANE et n'en lie aucun.

Le paquet contient 15 profils de scanner. Ils ont été construits à partir de films que j'ai photographiés moi-même, et le nombre de données enregistrées est de 928.

L'état est partout `realOnly`. Cela signifie qu'ils ont bien été construits à partir de vraies numérisations, mais qu'ils n'en sont pas au stade d'une précision vérifiée par une référence indépendante. Je ne voulais pas présenter comme vérifié ce qui ne l'est pas. Les profils ne s'attachent pas automatiquement d'après un nom de scanner, il faut donc les choisir soi-même.

Le détail est écrit dans la [documentation des profils de film](docs/fr/product/FILM_PROFILES.md).

## Documentation

- [Chroma Engine](docs/fr/product/CHROMA_ENGINE.md) | base du film, inversion, traitement des couleurs et ordre de développement
- [GrainMend](docs/fr/product/GRAINMEND.md) | détection et réparation des défauts, IR, historique des retouches
- [Profils de film](docs/fr/product/FILM_PROFILES.md) | analyse des sources et génération des profils
- [De la photothèque à l'impression](docs/fr/product/WORKFLOW.md) | import, synchronisation des dossiers, développement par lot, impression
- [Architecture produit](docs/fr/architecture/PRODUCT_ARCHITECTURE.md) | structure de l'application, du moteur, du stockage et de l'export
- [Toute la documentation](docs/fr/README.md) | multilingue (6 langues)

## Compiler soi-même

Les outils et les commandes diffèrent selon la plateforme. La procédure complète est dans chaque documentation. [macOS](negaflow-mac/docs/README_fr.md) demande macOS 14 ou ultérieur et Xcode 26, [Windows](negaflow-windows/docs/README_fr.md) demande Windows 11 24H2, Visual Studio 2022 et le SDK .NET 10. Les règles de travail du dépôt sont réunies dans [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Licence

**negaflow** est distribué sous [licence Apache 2.0](LICENSE). Il n'est ni affilié ni sponsorisé par Kodak, Fujifilm, Noritsu, LaserSoft Imaging ni aucun autre détenteur de marque. Les noms de produits ne sont employés que pour désigner ce avec quoi une chose est compatible ou ce par rapport à quoi elle est mesurée. La [note sur les marques](TRADEMARKS.md) le détaille.
