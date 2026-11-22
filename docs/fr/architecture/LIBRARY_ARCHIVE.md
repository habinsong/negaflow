# Archive de bibliothèque

[Accueil de la documentation](../README.md)

Une sauvegarde du catalogue remet l'application en marche et ne contient pas les photos d'origine. Les deux plateformes écrivent `.negaflowarchive`, mais avec un format et un contenu différents entre macOS et Windows.

> [!WARNING]
> Si la création de l'archive échoue, les originaux, les XMP tiers, le catalogue en cours et toute archive existante restent intacts.

## Archive macOS (dossier BagIt)

Sur macOS, `.negaflowarchive` est un dossier qui suit l'arborescence de [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) et rassemble le catalogue avec les photos référencées.

| Inclus | Exclus |
|---|---|
| JSON de catalogue portable | Le fichier SQLite en cours d'utilisation |
| Originaux référencés et originaux IR restants | Vignettes et aperçus |
| Recettes de défauts GrainMend | Caches GrainMend reconstructibles |
| Liens entre copies virtuelles et originaux partagés | Fichiers exportés |

Les fichiers de contenu et les fichiers d'étiquettes ont des manifestes SHA-256 distincts (`manifest-sha256.txt` et `tagmanifest-sha256.txt`). `negaflow-archive.json` relie les identifiants de vues aux identifiants de fichiers stockés. Les copies virtuelles d'un même original partagent une seule copie stockée.

L'écriture refuse d'écraser une destination déjà présente. Le dossier temporaire n'est déplacé vers son emplacement final qu'une fois toutes ces vérifications passées :

1. L'application actuelle peut lire le catalogue en sécurité.
2. Les originaux et les entrées IR sont des fichiers ordinaires dont la taille et la date de modification ne changent pas pendant la copie.
3. Chaque recette de défauts GrainMend nécessaire est lisible.
4. Les hachages SHA-256 (`manifest-sha256.txt`, `tagmanifest-sha256.txt`), tailles en octets, liste de fichiers et `Payload-Oxum` concordent.
5. Les liens entre vues, originaux, fichiers IR et recettes GrainMend correspondent au catalogue.

En cas d'échec, seul le dossier temporaire inachevé est supprimé.

## Archive Windows (fichier ZIP)

Sur Windows, `.negaflowarchive` est une archive ZIP contenant l'état du catalogue et des défauts. Elle ne copie pas les fichiers photo d'origine.

| Inclus | Exclus |
|---|---|
| `library.sqlite` | Fichiers photo d'origine et originaux IR |
| Recettes `defects/*` | Vignettes, aperçus et caches reconstructibles |
| `archive.json` (tailles en octets et hachages SHA-256 par entrée) | Fichiers exportés |

Windows écrit l'archive dans un fichier temporaire puis remplace la destination de manière atomique en cas de succès. En cas d'échec, le fichier temporaire est supprimé et toute archive existante reste intacte.

## Limites

Les archives `.negaflowarchive` de macOS et de Windows utilisent des formats et des schémas de catalogue distincts : une archive se déplace entre machines de la même plateforme. Les formats d'origine sont conservés tels quels, sans conversion pour la compatibilité à long terme. Les événements de préservation PREMIS, les enregistrements d'agents et la migration vers des formats recommandés sortent du périmètre de la v1.

Une archive n'est pas un plan de préservation. Gardez des copies sur d'autres supports et à un autre endroit, et revérifiez les hachages régulièrement.

Sources :

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
