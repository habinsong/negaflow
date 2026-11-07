# Documentation de negaflow

Classée par sujet pour ouvrir directement celle qu'il vous faut.

[English](../README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [简体中文](../zh-Hans/README.md) · Français · [Deutsch](../de/README.md)

> [!NOTE]
> negaflow 1.2.6 tourne sur macOS et Windows. Les deux applications sont écrites séparément et rendent la même image à partir du même fichier.

## Plateforme

| Document | À lire quand |
|---|---|
| [Ce qui diffère entre les versions macOS et Windows](platform/PLATFORM_DIFFERENCES.md) | Vous voulez savoir ce qui est identique et ce qui ne l'est pas |
| [Documentation macOS](../../negaflow-mac/docs/README_fr.md) | Vous installez, compilez ou utilisez la CLI sur macOS |
| [Documentation Windows](../../negaflow-windows/docs/README_fr.md) | Vous installez, compilez ou vérifiez le moteur sur Windows |

## Produit

| Document | À lire quand |
|---|---|
| [De la bibliothèque au tirage](product/WORKFLOW.md) | Vous avez besoin du comportement de l'import, du développement par dossier, du copier-coller et du tirage |
| [Chroma Engine](product/CHROMA_ENGINE.md) | Vous voulez l'inversion du film et l'ordre de développement |
| [GrainMend](product/GRAINMEND.md) | Vous voulez voir comment fonctionne la réparation des poussières et des rayures |
| [Profils de film](product/FILM_PROFILES.md) | Vous voulez connaître l'origine et les limites des profils fournis |

## Architecture

| Document | À utiliser quand |
|---|---|
| [Architecture produit](architecture/PRODUCT_ARCHITECTURE.md) | Flux de données entre application, moteur, stockage et export |
| [Stockage du catalogue](architecture/CATALOG_STORAGE.md) | Catalogue SQLite, import de l'ancien catalogue JSON, mesures |
| [Architecture des plugins scanner](architecture/SCANNER_PLUGINS.md) | Processus externe, approbation, publication des fichiers de numérisation |
| [Archive de bibliothèque](architecture/LIBRARY_ARCHIVE.md) | Originaux et historique des retouches stockés ensemble |

## Référence

| Document | Contenu |
|---|---|
| [JSON de la CLI scanner](reference/CLI_JSON.md) | Sortie de `detect --json` et `capabilities --json` |
| [Manifeste de rendu](reference/RENDER_MANIFEST.md) | Liens SHA-256 entre source, valeurs de retouche et fichier de sortie |
| [Mises en page de tirage et aperçu C-print](reference/C_PRINT.md) | Huit mises en page, export de page finie, ICC d'épreuve seul, limites de précision |
| [Réponse négative](reference/PRINT_RESPONSE.md) | Formule et ancrages de `shoulder-print-response-v4` |
| [Contrôle qualité des profils scanner](reference/PROFILE_QUALITY_GATE.md) | Règles de publication pour les paires REAL/TARGET |
| [Profils de bruit des scanners](reference/SCANNER_NOISE_PROFILES.md) | Mesure par numérisations répétées et conditions d'application |
| [Films que GrainMend IR doit éviter](reference/INFRARED_LIMITS.md) | Noir et blanc, Kodachrome, limites d'alignement RVB/IR |
| [Comment la détection des vues sur scanner à plat trouve le film](reference/FRAME_DETECTION.md) | Film ou porte-film vide, limites des vues |
| [Validation colorimétrique IT8](reference/IT8_COLOR_VALIDATION.md) | Mesure des plages, niveaux de preuve, régression synthétique |

## Provenance et distribution

| Document | Contenu |
|---|---|
| [Provenance du code et des ressources](legal/PROVENANCE.md) | Vous vérifiez la frontière Apache/GPL ou les empreintes des ressources fournies |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | Vous vérifiez l'usage des noms de films, de scanners et de produits |

## Comment c'est écrit

- Les documents produit décrivent ce que l'utilisateur voit aujourd'hui.
- Les documents d'architecture décrivent les responsabilités et le flux des données.
- Les documents de référence gardent tels quels les valeurs de code, les noms de champs et les empreintes.
- Les documents de validation séparent ce qui a réussi de ce qui n'est pas vérifié.
- Une section présente dans une langue l'est dans les six.
