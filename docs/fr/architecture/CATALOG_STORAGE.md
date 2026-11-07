# Stockage du catalogue

[Accueil de la documentation](../README.md)

Le stockage principal est `library.sqlite`. L'ancien `library.json` ne sert qu'à importer un ancien catalogue ou à écrire un fichier de diagnostic. Rien ne met à jour les deux à la fois : il n'y a donc pas de dual-write. Les sauvegardes et archives de conservation utilisent du JSON portable et excluent le fichier SQLite en cours d'utilisation.

| Type | Format | Usage |
|---|---|---|
| Catalogue principal | SQLite | Exécution de l'application, recherche, enregistrement, récupération |
| Anciennes données | JSON | Importer un catalogue existant |
| Sauvegarde et archive de conservation | Forme JSON | Déplacement vers une autre machine, restauration |

> [!IMPORTANT]
> Un catalogue manquant ou endommagé ne déclenche pas le démarrage d'une bibliothèque vide. Le catalogue d'origine et les fichiers photo restent intacts tant qu'aucune génération saine n'est trouvée.

## Mesures

JSON et SQLite ont été comparés sur le même Mac avec ces commandes.

<details>
<summary>Commandes de mesure</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_CATALOG_PERF_REPORT="$PWD/build/performance/catalog.json" \
  bash scripts/performance/run-catalog.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_LIBRARY_QUERY_PERF_REPORT="$PWD/build/performance/library-query.json" \
  bash scripts/run-library-query-performance.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_SQLITE_CATALOG_PERF_REPORT="$PWD/build/performance/catalog-sqlite.json" \
  bash scripts/performance/run-sqlite-catalog.sh
```

</details>

Mesuré le 2026-07-12 : Mac14,3, arm64, 8 cœurs, 24 Gio, macOS 26.5, build Swift Release. Ces chiffres servent de référence de non-régression pour cette configuration, pas de prévision pour un autre Mac.

| Vues | Taille du JSON | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

L'encodage de 50 000 vues en JSON a augmenté la mémoire résidente d'environ 191 Mio et le RSS maximal d'environ 107 Mio. Sur les mêmes données, la préparation de la recherche en mémoire a pris 32,86 ms, le tri de tous les noms 86,01 ms et le tri des noms après un filtre 158,37 ms. Quatre projections de filtre à la suite ont eu un p50 de 512,80 ms.

Le stockage par lignes SQLite à 50 000 vues, p95 en Release :

| Opération | p95 |
|---|---:|
| Nouvelle validation | 3,714 ms |
| Lecture du fichier principal | 7,446 ms |
| Validation sans changement | 3,856 ms |
| Taille par vue | ≈ 4,211 bytes |

Une sauvegarde ne charge pas toute la base dans `Data`. Elle crée une copie temporaire compatible avec la réplication, puis la substitue de façon atomique. La vérification avant sauvegarde contrôle l'intégrité SQLite et le schéma au lieu de décoder chaque vue, ce qui a ramené le p95 d'une validation sans changement de 11 245 ms à 3 856 ms.

## Pourquoi SQLite

- De nombreux changements de lignes tiennent dans une transaction.
- Les lignes et les index permettent de ne lire que les vues nécessaires.
- L'API C de SQLite est fournie avec macOS : aucun nouveau paquet n'est nécessaire.
- La règle de récupération est conservée : un stockage endommagé n'est jamais traité comme une bibliothèque vide.

Il fonctionne avec `journal_mode=DELETE` et `synchronous=FULL`. Avec WAL, la base et le fichier `-wal` devraient être traités comme un seul bloc. La base en cours d'utilisation n'est pas copiée directement. Seul le fichier principal, vérifié après la fermeture de la connexion, devient une copie de récupération.

## Qui fait quoi dans le code

- `CatalogStore` : connexion, transactions, version du schéma, contrôles d'intégrité
- `CatalogMigration` : import JSON en lecture seule et conversion par version
- Tables d'entités : vues, originaux, ordre, bobines, dossiers, collections, recherche, tâches de numérisation
- `LibraryBackupStore` : sauvegarde JSON portable, vérifications avant restauration, informations de récupération

Les valeurs de développement et l'historique de retouches versionné sont stockés en BLOB JSON par entité. Les pixels sources, les vignettes et les caches GrainMend restent hors de la base. Il manque encore des colonnes et des index pour la recherche et le tri : tout le catalogue est chargé en mémoire au démarrage, et le temps de lecture SQLite ressemble donc à celui du JSON. L'étape suivante est une recherche par index qui ne lit que les colonnes et les vues utilisées.

## Reprendre l'ancien JSON

1. Vérifier la version du JSON et `LibraryCatalogHealth`.
2. Créer un SQLite temporaire.
3. Déplacer les données en une seule transaction.
4. Comparer les identifiants, l'ordre, l'appartenance et les tâches.
5. Vérifier `integrity_check` et les conditions de sécurité.
6. Garder le JSON comme génération de récupération.
7. Basculer sur SQLite comme stockage principal.

Si une étape échoue, le JSON existant reste tel quel et un catalogue vide n'est jamais démarré. Même si des fichiers et marqueurs intermédiaires subsistent, le travail ne reprend que si le SHA-256 de la source et les deux catalogues concordent. Après la migration, il n'y a pas de repli automatique sur le JSON. La version minimale de lecture et le marqueur de migration sont contrôlés pour qu'une application plus ancienne ne modifie pas le JSON et ne scinde pas le stockage en deux.

## Sources

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
