# État du projet

[Accueil de la documentation](../README.md)

C'est le document de référence pour ce qui est fait et ce qui a été vérifié. Le README explique le
produit et son usage ; les documents de docs portent les spécifications et les décisions détaillées.

## Informations de base

| Élément | Valeur actuelle |
|---|---|
| Version | `1.0.9` |
| Build | `1` |
| Système | macOS 14 ou plus récent |
| Déroulé | import ou scan → développement → export |
| Développement par défaut | `main`, correction manuelle |
| Originaux | Les fichiers d'origine et les fichiers annexes tiers ne sont pas modifiés |

> [!WARNING]
> L'étiquette `1.0.9` et un build réussi ne signifient pas que la compatibilité avec un scanner
> réel, la qualité d'image finale, la signature externe ou la notarisation ont été confirmées.
> Le matériel réel et l'approbation de publication sont consignés dans la checklist plus bas.

## Fait, et vérifié automatiquement

- Catalogue non destructif, fichiers annexes, copies virtuelles, collections, films, notes, sélection et rejet
- Import en double, reliaison des originaux, retrait de la bibliothèque, mise à la corbeille des originaux
- Contrôle de santé du catalogue, verrou de processus, blocage de récupération, générations de sauvegarde, répétition de restauration, redéveloppement des images sélectionnées
- Chemin commun de développement et d'export, métadonnées, historique de traitement, historique d'édition, sortie multi-fichiers
- JPEG encodé sans sous-échantillonnage de chrominance à partir de 95 % de qualité, PNG en 8 ou 16 bits au choix, et un export rapide qui suit ses propres réglages d'encodage
- Appareil, objectif, film et exposition notés puis écrits dans le fichier exporté ; dans l'EXIF, l'appareil de prise de vue prime sur le scanner
- Notes du rouleau ne remplissant que les champs vides d'une vue, avec code de rouleau, film et appareil comme jetons de nom de fichier
- Originaux iCloud évincés rapatriés avant un export, et vérification d'export standard ou stricte
- Sélection de vue sur un aperçu à plat verrouillée sur le rapport du format de film choisi
- Détection automatique des vues à plat qui reconnaît le film à son grain et à son image plutôt qu'à sa luminosité, écarte les fenêtres vides et les fenêtres coupées en deux, et mesure l'écart entre les vues au lieu de le deviner
- Nettoyage infrarouge proposé pour tout film à image de colorants, négatif couleur comme diapositive couleur, et refusé au noir et blanc à image argentique
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
- Progression de l’import, développement automatique désactivé par défaut et réglage conservé
- État replié des dossiers, défilement interne des photos dans Développement et même retrait de bibliothèque partout
- Déplacement entre dossiers importés, créés par l’app ou issus du scanner, avec nom numéroté en cas de collision
- Détection des déplacements et renommages dans le Finder, reliaison par signet et relecture du seul dossier modifié
- Application du procédé et de la cible par dossier, y compris aux photos déjà développées, avec progression
- Préréglages et copier-coller multiple incluant procédé, cible, corrections, recadrage et orientation
- Vignettes scanner développées dans Développement et Impression pour tous les types de film pris en charge
- Sans plugin scanner, la barre latérale commune reste masquée, mais la nouvelle recherche et le simulateur restent accessibles
- Les grands catalogues évitent les longs sauts automatiques, créent les lignes à la demande et disposent d’un test optionnel de 2 000 images en pixels réels
- Aperçu du profil sur chaque placement et conversion ICC imprimante de la page composée entière
- Séparation empêchant le profil d’épreuve C-print d’entrer dans Développement ou le fichier livré
- Sept mises en page : image unique, planche-contact, package d’images, package personnalisé, cyanotype, plaque de verre et gélatino-argentique
- Pages verticales pour les sélections multiples individuelles et même rendu historique dans Export et Exportation rapide
- Comptage par page terminée : 39 photos donnent une page contact 6 × 7, 10 pages à quatre images, une page personnalisée par défaut ou 39 fichiers individuels
- Réutilisation des aperçus, préparation limitée à deux à quatre sources, graphe Core Image jusqu’à la page et budget de 512 MiB de rasters source par page
- Fenêtre À propos localisée avec le message du bicentenaire de Niépce en gras entre le nom du produit et la version

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
- [Détection des vues sur scanner à plat](../reference/FRAME_DETECTION.md)

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

`scripts/run-app.sh build` assemble seulement l’application. Il ne lance ni l’application ni un
Runner de test UI ; l’automatisation GUI ne démarre qu’avec la commande séparée
`scripts/run-gui-e2e.sh`.

Au 31 juillet 2026, l’arbre de travail courant a passé le build Swift en concurrence stricte,
1 800 tests parallèles et 9 tests sériels sensibles au temps. `scripts/run-app.sh build` a aussi
produit une nouvelle app Release arm64, avec des UUID identiques pour l’exécutable et le dSYM.
Cela ne remplace pas les contrôles GUI, scanner réel, Developer ID ou notarisation.

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

Le 31 juillet 2026, le test optionnel `PrintExportPerformanceTests` a utilisé sur ce Mac 39 sources
TIFF distinctes de 4 000 × 3 000 et une sortie JPEG à 300 DPI :

| Sortie Tirage | Export | Exportation rapide |
|---|---:|---:|
| Planche-contact 6 × 7, 39 photos → 1 fichier | 1,177 s | — |
| Image unique, 39 photos → 39 fichiers | — | 5,234 s |
| Cyanotype, 39 photos → 39 fichiers | 5,467 s | 5,659 s |
| Plaque de verre, 39 photos → 39 fichiers | 5,960 s | 6,278 s |
| Gélatino-argentique, 39 photos → 39 fichiers | 6,732 s | 6,697 s |

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
checklist QA sur matériel réel.

## Quel document fait référence

| Sujet | Document de référence |
|---|---|
| Implémentation et vérifications actuelles | Ce document |
| Bibliothèque, développement par dossier, copie des réglages et tirage | [De la bibliothèque au tirage](WORKFLOW.md) |
| Spécification de l'hôte scanner | [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md) |
| JSON de la CLI scanner | [JSON de la CLI scanner](../reference/CLI_JSON.md) |
| Mode de stockage du catalogue | [Stockage du catalogue](../architecture/CATALOG_STORAGE.md) |
| Règles de publication des profils scanner | [Contrôle qualité des profils scanner](../reference/PROFILE_QUALITY_GATE.md) |
| Implémentation et limites de GrainMend | [GrainMend](GRAINMEND.md) |
| Approbation du rendu final et du matériel réel | Checklist QA sur matériel réel |
| Installation et usage | Les fichiers README à la racine du dépôt |
