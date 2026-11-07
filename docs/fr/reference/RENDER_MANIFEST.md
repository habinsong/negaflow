# Manifeste de rendu

[Accueil de la documentation](../README.md)

Le `renderManifest` du fichier annexe relie la source, les valeurs de retouche et le fichier final par SHA-256. Les chemins de fichiers ne sont pas enregistrés.

> [!IMPORTANT]
> Le `renderManifest` consigne des liens de hachage entre fichiers et réglages. Il n'a ni signature numérique ni certificat : ce n'est pas du C2PA Content Credentials.

## Contenu de la v3

- Taille en octets de la source, SHA-256 et nom de l'algorithme `sha-256`
- L'entrée de rendu réellement utilisée
- La portée vérifiée du fichier de cache GrainMend ou de l'entrée en mémoire
- SHA-256 des réglages de développement, de GrainMend et d'export
- SHA-256 du profil de scanner
- Origine du décodeur et version du moteur de rendu Chroma Engine
- SHA-256, taille en octets, dimensions en pixels et format du fichier final

Une fois l'encodeur terminé, le fichier est rouvert avec ImageIO pour confirmer ses dimensions, puis haché en entier. Le fichier annexe est écrit après. Si la vérification v3 échoue, le résultat n'est pas publié comme jeu de sortie terminé.

## Entrée GrainMend

- `cleanedMemory` : les pixels en mémoire n'ont pas de hachage standard, la portée vérifiée est donc notée `sourceAndDevelopRecipe`. Le SHA-256 de l'historique des retouches GrainMend est toujours inclus.
- `cleanedFile` : le fichier de cache GrainMend entier et l'historique des retouches sont tous deux hachés.

Les fichiers v1 et v2 s'ouvrent toujours. Les hachages qui n'existaient pas alors ne sont pas ajoutés après coup.

## Différence avec C2PA

Il n'y a ni signature numérique, ni certificat, ni chaîne de confiance, ni magasin de déclarations intégré, seulement des SHA-256 vérifiables. Le hard binding et l'historique de traitement de C2PA, ainsi que l'idée d'intégrité de PREMIS, ont servi de référence.

Sources :

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
