# Documentation negaflow

Classée par sujet pour ouvrir directement celle qu'il vous faut.

[English](../README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [简体中文](../zh-Hans/README.md) · Français · [Deutsch](../de/README.md)

```mermaid
flowchart LR
    A["Je veux connaître le produit"] --> P["product"]
    B["Je veux le code et les données"] --> R["architecture"]
    C["Je veux les formats et les valeurs"] --> S["reference"]
```

> [!NOTE]
> negaflow 1.1.3 tourne sur macOS et sur Windows. Les deux applications sont écrites séparément pour leur plateforme et rendent la même image à partir du même fichier.

## Plateforme

| Document | À lire quand |
|---|---|
| [Ce qui diffère entre macOS et Windows](platform/PLATFORM_DIFFERENCES.md) | Vous voulez savoir ce qui est identique et ce qui ne l'est pas |
| [Documentation macOS](../../negaflow-mac/docs/README_fr.md) | Vous installez, compilez ou utilisez la CLI sur macOS |
| [Documentation Windows](../../negaflow-windows/docs/README_fr.md) | Vous installez, compilez ou vérifiez le moteur sur Windows |

## Produit

| Document | À lire quand |
|---|---|
| [De la photothèque à l’impression](product/WORKFLOW.md) | Pour l’import, le développement par dossier, le copier-coller et l’impression |
| [Chroma Engine](product/CHROMA_ENGINE.md) | Vous voulez l'inversion du film et l'ordre de développement |
| [GrainMend](product/GRAINMEND.md) | Vous voulez voir comment la réparation poussière et rayures fonctionne |
| [Profils de film](product/FILM_PROFILES.md) | Vous voulez l'origine des profils fournis et leurs limites |

## Architecture

| Document | Contenu |
|---|---|
| [Architecture produit](architecture/PRODUCT_ARCHITECTURE.md) | Flux de données entre application, moteur, stockage et export |
| [Stockage du catalogue](architecture/CATALOG_STORAGE.md) | Pourquoi SQLite, l'ancien format, les mesures |
| [Architecture des plugins scanner](architecture/SCANNER_PLUGINS.md) | Processus externe, approbation, fichiers de scan publiés |
| [Archive de bibliothèque](architecture/LIBRARY_ARCHIVE.md) | Comment originaux et historique d'édition sont conservés ensemble |

## Référence

| Document | Contenu |
|---|---|
| [JSON de la CLI scanner](reference/CLI_JSON.md) | Forme de sortie de `detect --json` et `capabilities --json` |
| [Manifeste de rendu](reference/RENDER_MANIFEST.md) | Liens SHA-256 entre source, valeurs d'édition et fichier de sortie |
| [Mises en page et aperçu C-print](reference/C_PRINT.md) | Sept mises en page, export par page, rendu optimisé, profil ICC d’épreuve et limites de précision |
| [Réponse de tirage fixe](reference/PRINT_RESPONSE.md) | Formule et points d'ancrage de `shoulder-print-response-v4` |
| [Contrôle qualité des profils scanner](reference/PROFILE_QUALITY_GATE.md) | Règles de publication du matériel REAL/TARGET |
| [Profils de bruit des scanners](reference/SCANNER_NOISE_PROFILES.md) | Mesure par scans répétés et conditions d'application automatique |
| [Films que GrainMend IR doit éviter](reference/INFRARED_LIMITS.md) | Noir et blanc, Kodachrome, limites d'alignement RVB/IR |
| [Détection des vues sur scanner à plat](reference/FRAME_DETECTION.md) | Comment le film est distingué d'un porte-films vide et comment les limites de vue sont mesurées |
| [Validation colorimétrique IT8](reference/IT8_COLOR_VALIDATION.md) | Mesure des patchs, niveaux de preuve, régression synthétique |

## Provenance et distribution

| Document | À utiliser quand |
|---|---|
| [Provenance du code et des ressources](legal/PROVENANCE.md) | Vous vérifiez la frontière Apache/GPL et les empreintes des ressources |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | Vous vérifiez l'usage des noms de films, scanners et produits |

## Comment c'est écrit

- Les documents produit ne décrivent que ce que l'utilisateur voit aujourd'hui.
- Les documents d'architecture décrivent les responsabilités et le déplacement des données.
- Les valeurs de code, noms de champs et empreintes restent tels quels.
- Les documents de validation séparent ce qui est passé de ce qui reste à vérifier.
- Des phrases simples. Pas d'adjectifs publicitaires, pas de paragraphe de conclusion, pas de parallélisme négatif.
- Une section présente dans une langue l'est dans les six.
