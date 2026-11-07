# Architecture des plugins scanner

[Accueil de la documentation](../README.md)

L'entrée par défaut de negaflow est l'import d'images. Un vrai scanner n'est connecté que si un module externe est présent.

> [!IMPORTANT]
> L'application ne devine pas les capacités d'après le nom de modèle d'un scanner. Seul ce que le module déclare passe dans l'écran et les requêtes, et l'appareil de démonstration n'apparaît que si vous choisissez vous-même le mode démo.

## Composants

| Composant | Rôle |
|---|---|
| Import d'images | Envoie RAW, DNG, TIFF, PNG et JPEG vers le chemin de développement. |
| Module externe | Tourne dans son propre processus, pilote l'appareil réel et parle JSON. |
| Scanner de démonstration | Fournit `negaflow Scanner` et `negaflow Flatbed Scanner` pour le développement. Il faut choisir la démo pour l'utiliser. |
| Liaison ImageCaptureCore | Code de compatibilité inactif pour les appareils Capture d'image de macOS. |

Ce dépôt ne contient aucune implémentation SANE. Ce code se trouve dans un projet GPL séparé :

- <https://github.com/habinsong/negaflow-scanner-sane>

## Comment ça se connecte

L'écran parle à `ScannerKit`, qui aiguille vers l'un de trois backends :

1. `ExternalScannerBackend`, qui exécute le module externe installé.
2. `MockScannerBackend`, qui produit des images synthétiques pour le développement.
3. `InactiveImageCaptureBackend`, inactif pour l'instant.

L'écran ne voit que `ScannerBackend`. L'identifiant d'appareil d'un module apparaît dans l'application sous la forme `plugin:<pluginId>:<deviceId>`.

Quand le module s'exécute, `plugin:<pluginId>:` est retiré et seul l'identifiant d'appareil propre au module est envoyé.

## Trouver les modules

Le dossier par défaut est `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`. Pour les tests et le développement local, `NEGAFLOW_PLUGINS_DIR` désigne un autre dossier.

| Champ | Règle |
|---|---|
| `schemaVersion` | Exactement `1` aujourd'hui |
| `protocolVersion` | `1` si omis ; `1` et `2` sont pris en charge |
| `id` | Identifiant unique du module |
| `name` | Nom affiché à l'écran |
| `kind` | Type de module |
| `license` | Licence de distribution |
| `homepage` | Adresse du projet |
| `executable` | Chemin de l'exécutable |

`id` fait de 1 à 64 caractères ASCII. Le premier est une lettre ou un chiffre, les suivants des lettres, des chiffres, `.`, `_` ou `-`. `:` sépare les identifiants d'appareil et n'est donc pas permis.

Un module ne s'ouvre que si le manifeste et l'exécutable sont tous deux valides. Les schémas anciens ou futurs et les protocoles inconnus ne sont pas lus au jugé.

### Contrôles de sécurité des fichiers

> [!WARNING]
> Si les octets du manifeste ou de l'exécutable changent, l'approbation précédente est annulée. Propriétaire, droits, présence de liens symboliques et SHA-256 sont revérifiés juste avant l'exécution.

- Le dossier du module, le manifeste et l'exécutable doivent appartenir à l'utilisateur courant.
- Un accès en écriture pour le groupe ou les autres est refusé.
- Les liens symboliques sont refusés.
- Le SHA-256 du manifeste et de l'exécutable est enregistré.
- L'utilisateur approuve le module à la première utilisation.
- Des octets modifiés annulent l'approbation.
- Les identifiants sont recalculés juste avant l'exécution.

## Commandes

Le module s'exécute comme un processus séparé.

| Commande | Résultat |
|---|---|
| `detect` | Liste JSON des appareils |
| `capabilities <deviceId>` | Liste JSON des capacités. Peut recevoir sur stdin le JSON (identifiant, fabricant, modèle) rapporté par `detect` |
| `scan` | JSON des réglages sur stdin ; NDJSON de progression et résultat final sur stdout |

## Protocole de numérisation

### Version 1

L'ancienne spécification de compatibilité. Les requêtes et le NDJSON n'ont ni `protocolVersion`, ni `requestID`, ni `sequence`. Elle ne peut pas signaler les réglages réellement appliqués : le résultat est donc enregistré comme `.unknownLegacy(protocolVersion: 1)`. Les valeurs de la requête ne sont pas recopiées comme si elles avaient été vérifiées.

### Version 2

Utilisée seulement si le manifeste porte `"protocolVersion": 2`.

Une requête contient :

- `protocolVersion: 2`
- Un UUID `requestID` créé par l'application

Une réponse `capabilities` peut renvoyer le champ facultatif `capabilityToken`. L'application ne l'interprète pas. Elle le transmet tel quel à la prochaine requête `scan` v2 du même appareil, et nulle part ailleurs. Il est absent des requêtes v1, et les jetons ne sont jamais mélangés entre appareils. Le module doit vérifier lui-même le format et la validité du jeton.

Pour éviter une reconnexion erronée à un autre modèle du même backend, l'application renvoie le `deviceID`, le `vendor` et le `model` du dernier `detect` comme JSON facultatif sur stdin de `capabilities`. Les modules existants peuvent ignorer cette entrée. Un module dont l'adresse d'appareil peut changer devrait lier cette identité à l'instantané de capacités et la revérifier au `scan` suivant.

Chaque événement NDJSON répète la même version et le même identifiant de requête, et porte un `sequence` supérieur ou égal à zéro, plus grand que le précédent. Seuls `progress`, `result` et `error` sont permis. `result` et `error` sont des événements finaux, et tout ce qui suit échoue. Une numérisation qui ne s'est pas terminée par une erreur a exactement un `result`.

Tous ces cas échouent par fermeture :

- Un événement illisible
- Une version ou un identifiant de requête manquant ou différent
- Un sequence répété ou hors ordre
- Un événement inconnu
- Un résultat en double
- Une sortie en trop après l'événement final
- De l'UTF-8 invalide

Une violation de la spécification v2 met fin au module immédiatement, sans attendre le délai habituel.

### Réglages réellement appliqués

Un `result` v2 doit porter `appliedOptions` :

- `deviceID`, `resolutionDPI`, `bitDepth`, `colorMode`, `filmType`
- `scanArea` : `originXMM`, `originYMM`, `widthMM`, `heightMM`, la zone que le module a réellement envoyée au backend. Un module peut l'ajuster de moins de 1 mm pour contourner un backend qui calcule mal la taille de numérisation. L'application compare la taille en pixels renvoyée à cette zone : recopier la requête rendrait le contrôle inopérant.
- `infrared`, `multiExposure`
- `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`
- `outputRawTIFF`

Pour ces trois derniers ajustements, les clés doivent être présentes même quand la valeur est `null`.

`resolutionDPI: 0` signifie aperçu. Un aperçu différent de 0 ou une numérisation complète à 0 est refusé. Les valeurs inconnues, un autre appareil, et une résolution, une profondeur ou un état IR qui diffèrent entre l'en-tête du résultat et `appliedOptions` sont refusés aussi.

Une fois les contrôles passés, l'application enregistre son propre identifiant de scanner et l'identifiant de requête à la place de celui du module, et garde le chemin de sortie final. Ce n'est qu'alors que le résultat est marqué `.verified(options)`.

En v1, `ScanResult.resolution` et `bitDepth` peuvent se rabattre sur les valeurs demandées. Les champs qui indiquent l'origine, `reportedResolution` et `reportedBitDepth`, ne prennent que des valeurs correctes que le résultat a rapportées lui-même.

## Zone de numérisation positionnée sur scanner à plat

L'aperçu de ce flux demande une résolution explicite, la valeur prise en charge la plus proche de 300 dpi, au lieu de la laisser à l'appareil. Une valeur par défaut peut descendre à 25 dpi, bien trop grossière pour placer ou détecter des vues. Un aperçu qui porte une résolution est une numérisation ordinaire : il n'utilise donc pas le chemin d'aperçu du module.

Une numérisation à plat avec position choisie ne s'active que si le module signale tout ceci :

- Aperçu
- `supportsPositionedScanArea`
- `scanOriginXRange` et `scanOriginYRange` en mm
- `scanWidthRange` et `scanHeightRange` en mm

L'application étend la zone choisie vers l'extérieur jusqu'au pas du module et crée une tâche de numérisation complète par zone. Elle ne devine jamais cela d'après un nom de modèle. Les anciens modules sans les champs facultatifs gardent le flux à vues fixes.

## Limites de processus et annulation

- Plafond de stdout : 4 Mio
- Plafond de stderr : 1 Mio

Dépasser le plafond termine le processus et échoue. Pendant le nettoyage, seuls les octets déjà arrivés sont lus. Même si un processus enfant a hérité du tube, rien n'attend l'EOF.

`cancelScan()` ne rend la main qu'une fois le module terminé, les gestionnaires de tube fermés et l'emplacement du travail suivant libéré.

## Publication du fichier de numérisation

Le module écrit l'image source exactement à l'`outputPath` donné par l'application et renvoie le même chemin dans le résultat. Ce chemin est un emplacement temporaire sur le même disque que le dossier final. Déroulement :

1. L'application envoie le JSON des réglages et l'`outputPath` au module.
2. Le module écrit le fichier de numérisation dans le dossier temporaire.
3. Le module renvoie un résultat portant le même `outputPath`.
4. L'application vérifie le format, la taille et le chemin.
5. Si les contrôles passent, elle publie le fichier de façon atomique dans le dossier final de numérisation. En cas d'annulation, d'échec ou de sortie erronée, elle supprime le matériel temporaire.

L'application confirme :

- Un fichier ordinaire non vide
- Une image qu'ImageIO sait lire
- Le format et la taille en pixels attendus
- Le même chemin dans la requête et le résultat

En cas d'annulation, de dépassement de délai, de sortie erronée ou d'échec du module, le dossier temporaire est supprimé et aucune numérisation partielle n'est publiée.

Un fichier IR v2 doit lui aussi se trouver dans le dossier temporaire fourni par l'application. Son type, sa lisibilité et sa taille en pixels sont vérifiés. La v1 peut accepter un chemin IR externe, par compatibilité avec les modules déjà diffusés.

## La frontière avec SANE

L'implémentation SANE, ses dépendances, sa configuration, le traitement propre aux appareils, les tests et la documentation de publication se trouvent tous dans le dépôt séparé [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

Ce projet publie un programme d'installation standard pour macOS 14+ qui utilise le SANE de base de Homebrew, et un programme d'installation Coolscan distinct pour macOS 26+ qui compile le SANE 1.4.0 officiel avec le correctif d'allocation minimal de `coolscan2`/`coolscan3` en amont. La voie standard ne bloque pas Coolscan de façon proactive, mais ne contient pas ce correctif.

Ce dépôt ne documente et ne vérifie que la spécification de processus externe, indépendante des appareils. Qui se contente d'importer des fichiers image n'a pas besoin de module scanner.

L'application negaflow ne lie pas l'implémentation SANE et ne la place pas dans sa distribution. Le module a son propre dépôt, son exécutable, sa distribution des sources et sa licence GPL. Ce document consigne la structure et ne tranche pas la question de l'œuvre dérivée. Avant une vraie publication, les fichiers des deux artefacts et le contrat de communication sont revérifiés.

## Vérifications

Les tests de l'application exécutent un faux module externe comme vrai processus et confirment :

- La recherche des modules
- La recherche des appareils
- Le câblage des capacités
- Les événements de progression
- Le résultat final
- Le nettoyage après annulation et échec

L'implémentation SANE est vérifiée à part, dans les tests SwiftPM et le build Release du dépôt du module.
