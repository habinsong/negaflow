# État du projet

[Accueil de la documentation](../README.md)

C'est le document de référence pour ce qui est fait et ce qui a été vérifié. Le README explique le
produit et son usage ; les documents de docs portent les spécifications et les décisions détaillées.

## Informations de base

| Élément | Valeur actuelle |
|---|---|
| Version | `1.0.0` |
| Build | `1` |
| Système | macOS 14 ou plus récent |
| Déroulé | import ou scan → développement → export |
| Développement par défaut | `main`, correction manuelle |
| Originaux | Les fichiers d'origine et les fichiers annexes tiers ne sont pas modifiés |

> [!WARNING]
> L'étiquette `1.0.0` et un build réussi ne signifient pas que la compatibilité avec un scanner
> réel, la qualité d'image finale, la signature externe ou la notarisation ont été confirmées.
> Le matériel réel et l'approbation de publication sont consignés dans la checklist plus bas.

## Fait, et vérifié automatiquement

- Catalogue non destructif, fichiers annexes, copies virtuelles, collections, films, notes, sélection et rejet
- Import en double, reliaison des originaux, retrait de la bibliothèque, mise à la corbeille des originaux
- Contrôle de santé du catalogue, verrou de processus, blocage de récupération, générations de sauvegarde, répétition de restauration, redéveloppement des images sélectionnées
- Chemin commun de développement et d'export, métadonnées, historique de traitement, historique d'édition, sortie multi-fichiers
- Une frontière d'observation à faible fréquence qui rafraîchit le bouton d'export selon l'état de développement et de retraitement
- Découverte et approbation des plugins scanner, contrôle des capacités, protocole v1/v2, annulation, limites de temps, plafonds de sortie
- Contrôle du propriétaire et des droits du plugin, et validation de la sortie temporaire
- Contrôle de cohérence entre le JSON scanner de la CLI et les capacités affichées dans l'application
- Accessibilité, état de sélection, taille du texte, adaptation à la taille de fenêtre, restauration de l'état d'écran
- Vues comparaison et sélection, piles de photos, revue des doublons candidats
- Archive de conservation BagIt contenant originaux, IR, enregistrements GrainMend et liens de copies virtuelles
- Manifeste de rendu v3 reliant source et sortie par SHA-256
- Diagnostics d'alignement IR et limites de compatibilité par film
- Mesure répétée du bruit scanner et spécification de validation distincte
- Nettoyage du cache d'images sous pression mémoire
- Diagnostics stricts de concurrence Swift dans la CI

## Catalogue

Le stockage principal est `library.sqlite`.
Un `library.json` existant est ouvert en lecture seule, contrôlé, sauvegardé, puis transféré vers un
SQLite temporaire.
Il ne devient stockage principal que si le contenu des deux catalogues et l'intégrité SQLite
concordent.

À la reprise d'un travail interrompu, des preuves discordantes font échouer en position fermée.
Le JSON reste le format d'échange transférable pour sauvegarde et archive, mais deux stockages
principaux ne sont jamais utilisés en même temps.

Le détail est dans [stockage du catalogue](../architecture/CATALOG_STORAGE.md).

## Scanners

Ce dépôt contient un hôte de processus externe indépendant des appareils et la spécification JSON.
L'implémentation SANE, ses dépendances, sa configuration et ses fichiers de distribution n'y sont
pas.
Ce code vit dans le projet GPL séparé
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

L'application n'affiche que ce que le plugin installé a signalé. Elle ne devine pas de capacités
d'après un nom de modèle.
Sauf si vous choisissez la démo, aucun faux scanner ne prend le relais.

Spécifications détaillées :

- [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md)
- [JSON de la CLI scanner](../reference/CLI_JSON.md)

## Build et publication

<details>
<summary>Contrôles locaux et commandes de publication</summary>

Contrôles locaux :

```bash
bash scripts/ci-gate.sh
bash scripts/run-app.sh build
bash scripts/run-gui-e2e.sh  # nécessite le mode Automation de macOS
```

Fabriquer les fichiers de publication :

```bash
bash scripts/build-release.sh
```

</details>

Un seul passage de `build-release.sh` construit les applications Apple Silicon (`arm64`) et
Universal (`arm64`, `x86_64`), puis écrit ZIP, PKG, DMG, dSYM et la liste SHA-256.
En local, la signature est ad-hoc.
Une vraie publication demande une signature Developer ID Application et une signature Developer ID
Installer.

Le workflow manuel `Distribution` utilise le Developer ID protégé et la clé d'API App Store Connect.
Il envoie l'archive de l'application, le DMG et le PKG à Apple, agrafe le ticket de notarisation,
puis revérifie les sommes de contrôle et Gatekeeper.
Sans exécution réelle du workflow et réponse d'Apple, rien n'est affirmé sur la signature externe et
la notarisation.

## Mesures de performance

Les contrôles de performance couvrent le catalogue, la recherche dans la bibliothèque, les réglages
en haute résolution, le travail par zone de GrainMend et un film de pixels réels.

Mesures Release récentes sur un Mac :

| Opération | Résultat |
|---|---:|
| Lecture JSON 50 000 images p95 | environ 7,4 s |
| Lecture SQLite 50 000 images p95 | environ 7,4 s |
| Commit SQLite 50 000 images p95 | environ 3,7 s |
| Commit SQLite sans modification p95 | environ 3,9 s |
| Filtre et tri par nom sur 50 000 images | environ 158 ms |
| Aperçu rapide de 48 images | environ 10,6 s, max RSS environ 504 Mio |
| Développement de 48 images | environ 20,9 s, max RSS environ 1 012 Mio |

Ces chiffres ne garantissent pas la performance d'un autre Mac.
De nouvelles mesures viennent de cette commande.

```bash
bash scripts/run-performance-suite.sh
```

Les limites macOS 26 arm64 de `Config/performance-budget-v1.json` sont des plafonds larges, faits
pour attraper les grosses régressions.
Les respecter ne veut pas dire que chaque latence est agréable à l'usage.

## Mesures GrainMend

Le matériel FILM-R v2 est figé par DOI, 44 paires, 437 570 872 octets et les informations MD5 de
Figshare.

Le chemin automatique de la version publiée tourne à la sensibilité 0.7 avec une limite de sécurité
contre la surdétection.
Voici la comparaison avec l'ancienne référence de régression à 3.0.

| Métrique | Ancienne référence 3.0 | Auto sûr 0.7 |
|---|---:|---:|
| Pixels dégradés pondérés | 0,792 % | 0,017 % |
| Pixels modifiés pondérés | 0,794 % | 0,043 % |
| Variation moyenne de PSNR | -1,688 dB | +0,466 dB |
| Pire variation de PSNR | -18,952 dB | -1,338 dB |
| Images améliorées / dégradées / identiques | 11 / 33 / 0 | 34 / 6 / 4 |

En plus du contrôle de régression observé, des planchers absolus s'appliquent : PSNR moyen et médian
à 0 dB ou mieux, au plus 10 images dégradées, et un pire cas à -1,5 dB ou mieux.
La limite de sécurité automatique a stoppé la réparation sur 3 images, et l'application oriente
alors vers le mode Guidé.

FILM-R valide le chemin automatique de GrainMend RGB, rien d'autre.
Ce n'est pas une base pour revendiquer une équivalence avec l'IR matériel ni la qualité d'alignement
RVB/IR d'un scanner réel.

Le workflow manuel `GrainMend corpus` récupère les 44 paires, exécute le chemin par défaut en
Release, puis fait le contrôle de régression et téléverse le rapport.

## Ce que les contrôles automatiques ne règlent pas

- Revue finale de l'interface aux tailles de fenêtre prises en charge et avec les réglages d'accessibilité
- Plugins et scanners réels
- Négatifs réels et qualité d'image IR
- Developer ID, notarisation, Gatekeeper, installation sur un Mac vierge
- Performance sur tous les Mac pris en charge

Le rendu final et le matériel réel relèvent de l'utilisateur.
Un build réussi ne les remplace pas ; les résultats vont dans la
[checklist QA sur matériel réel](../validation/REAL_QA_CHECKLIST.md).

## Quel document fait référence

| Sujet | Document de référence |
|---|---|
| Implémentation et vérifications actuelles | Ce document |
| Spécification de l'hôte scanner | [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md) |
| JSON de la CLI scanner | [JSON de la CLI scanner](../reference/CLI_JSON.md) |
| Mode de stockage du catalogue | [Stockage du catalogue](../architecture/CATALOG_STORAGE.md) |
| Règles de publication des profils scanner | [Contrôle qualité des profils scanner](../reference/PROFILE_QUALITY_GATE.md) |
| Implémentation et limites de GrainMend | [GrainMend](GRAINMEND.md) |
| Approbation du rendu final et du matériel réel | [Checklist QA sur matériel réel](../validation/REAL_QA_CHECKLIST.md) |
| Installation et usage | Les fichiers README à la racine du dépôt |
