# Archive de bibliothèque

[Accueil de la documentation](../README.md)

Une sauvegarde du catalogue remet l'application en marche et ne contient pas les photos d'origine. L'archive `.negaflowarchive` les réunit dans un seul paquet.

| Inclus | Exclus |
|---|---|
| JSON de catalogue portable | Le fichier SQLite en cours d'utilisation |
| Originaux référencés et originaux IR restants | Vignettes et aperçus |
| L'historique de retouches GrainMend encore utile | Caches GrainMend reconstructibles |
| Le lien entre copies virtuelles et originaux partagés | Fichiers exportés |

> [!WARNING]
> Si la création de l'archive échoue, l'archive existante n'est pas écrasée. Les originaux, les XMP tiers et le catalogue en cours ne sont pas touchés.

## Structure du paquet et vérifications

Le paquet suit l'arborescence de [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html). Les listes SHA-256 sont écrites séparément pour les fichiers de contenu et les fichiers d'administration. `negaflow-archive.json` relie les identifiants de vues aux identifiants de fichiers stockés. Les copies virtuelles d'un même original partagent une seule copie stockée.

Le dossier temporaire n'est déplacé vers son emplacement final qu'une fois toutes ces vérifications passées :

1. L'application actuelle peut lire le catalogue en sécurité.
2. Les originaux et les entrées IR sont des fichiers ordinaires dont la taille et la date de modification ne changent pas pendant la copie.
3. Chaque enregistrement GrainMend nécessaire est lisible.
4. SHA-256, tailles en octets, liste de fichiers et `Payload-Oxum` concordent.
5. Les liens entre vues, originaux, fichiers IR et enregistrements GrainMend correspondent au catalogue.

En cas d'échec, seul le dossier temporaire inachevé est supprimé. L'archive existante reste en place.

## Limites

Les formats d'origine sont conservés tels quels, sans conversion pour la compatibilité à long terme. Les événements de préservation PREMIS, les enregistrements d'agents et la migration vers des formats recommandés sortent du périmètre de la v1.

Une archive n'est pas un plan de préservation. Gardez des copies sur d'autres supports et à un autre endroit, et revérifiez les hachages régulièrement.

Sources :

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
