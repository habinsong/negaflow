# Provenance du code et des ressources

[Accueil de la documentation](../README.md)

Ce document consigne le périmètre de distribution Apache-2.0 de l'application negaflow. C'est un relevé de provenance pour revérifier le dépôt et les artefacts de publication, sans valeur d'avis juridique.

## Code

Le code d’intégration Swift, Python et shell de `negaflow-mac` est écrit pour negaflow. Le décodage des RAW de négatifs utilise une révision fixe et non modifiée de LibRaw sous forme de `libraw.dylib` remplaçable, distribuée sous CDDL-1.0. L’application inclut l’archive source, le script de compilation et les textes de copyright et de licence dans `Contents/Resources/licenses/libraw/`. Le code LibRaw n’est pas fusionné dans l’arbre Apache. Windows utilise la même révision ; les autres composants sont décrits dans [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md). Le fichier de test `CameraNativeRaw.dng` vient de l’entrée 2204 de raw.pixls.us sous CC0-1.0, avec un JSON de provenance adjacent, et reste exclu de l’application.

Si le fichier de mentions supplémentaires manque, la compilation et la création du paquet continuent avec un avertissement. Les licences amont et les sources correspondantes restent incluses.

L'inversion du film reprend les notions publiées de sensitométrie : densité, pied, partie droite, épaule. Les courbes et les coefficients viennent des quatre points d'ancrage photométriques de negaflow, pas des formules ou constantes d'un programme tiers. Les équations et la dérivation sont dans [réponse de tirage fixe](../reference/PRINT_RESPONSE.md).

Les fiches techniques constructeur publiées alimentent trois groupes de constantes film livrées : les préréglages Dmin et Dmax par pellicule (`FilmStockDmin`), les préréglages spectraux et de courbes caractéristiques noir et blanc (`BWFilmProfile`), ainsi que les paramètres physiques de grain et de FTM (`DigitalFilmPhysics`). Ces valeurs sont des lectures approchées des graphiques publiés par les fabricants, et `FilmStockDmin` marque chaque entrée `datasheetCurve` ou `estimated` pour que l'origine reste visible. Un nombre lu sur un graphique publié est un fait sur la pellicule, pas une copie du code ou du texte de quelqu'un, et une base film mesurée sur le scan l'emporte toujours sur ces valeurs.

GrainMend IR procède dans cet ordre.

1. Estimer seul le décalage entier entre RVB et IR.
2. Interpoler des moyennes IR tronquées par intervalle de `log(red)` pour obtenir une courbe non paramétrique de fuite de scène.
3. Soustraire la fuite de scène, puis calculer le contraste relatif à la moyenne locale.
4. Construire le masque de défauts à partir d'un seuil de bruit local tronqué, des composantes connexes et de l'orientation.

Ce code ne lie ni ne porte la correction IR de SANE. La littérature publiée et les pages produit servent de contexte pour confirmer les limites physiques du film et de l'infrarouge. Reprendre une méthode ou un principe est une chose, copier l'expression du code en est une autre. Le U.S. Copyright Office trace la même limite entre méthodes et systèmes et leur expression concrète.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Frontière du plugin SANE

L'application n'a pas de `scanimage`, pas d'en-têtes SANE, pas de configuration de backend, pas de code de traitement propre à un appareil. Elle parle au programme externe installé uniquement par un contrat JSON/NDJSON versionné. Le vrai travail SANE est publié dans un dépôt et un exécutable séparés sous GPL-2.0-or-later.

Être un processus séparé ne règle pas à soi seul la question de licence. La FAQ GNU dit qu'une communication par tube ou ligne de commande ressemble en général à des programmes distincts, mais que la réponse peut changer si la communication est trop intime. Le contrat n'échange donc que des requêtes indépendantes de l'appareil, des capacités, une progression et des informations de fichier de résultat, sans partager de structures de données SANE.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md)

Le contrôle de publication reconfirme qu'aucun plugin, exécutable SANE ou bibliothèque SANE ne s'est glissé dans le bundle. Le plugin livre de son côté ses propres `LICENSE`, `COPYING`, le code source correspondant complet et les avis tiers.

## Ressources fournies

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) fige l'origine déclarée, la licence et le SHA-256 de chaque ressource qui entre dans l'application et l'arborescence source.

| Ensemble | Origine | Ce qui est livré |
|---|---|---|
| TIFF ScannerKit | Matériel de mise en page photographié et préparé par le mainteneur | 4 fichiers TIFF |
| Icône de l'application | Illustration du projet, fournie par le mainteneur | PNG source, PNG de build, ICNS |
| Préréglages de rendu | Valeurs écrites pour negaflow | 6 fichiers JSON |
| Profils de scanner | Construits à partir de mesures de scan conservées par le mainteneur | Profils numériques, sans les scans sources |

Les métadonnées d'appareil et d'espace colorimétrique visibles dans les TIFF sont des informations de conteneur issues de la prise de vue et de l'encodage. Le champ `sourceProfiles` d'un profil de scanner est le chemin logique du matériel de mesure local au moment de la construction, et ces photographies sources ne sont pas livrées.

Le matériel FILM-R v2 n'est téléchargé que pendant la mesure de qualité. Les images n'entrent ni dans le dépôt ni dans l'application. La version DOI, la licence CC BY 4.0, les tailles de fichiers et les empreintes sont figées dans [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json).

## Export DNG

Les écrivains DNG (`DNGLinearWriter` dans `negaflow-mac`, `dng_linear_export` dans `negaflow-windows`) sont écrits à partir des numéros de balises et du modèle colorimétrique de la Digital Negative Specification 1.6 publiée par Adobe. Ils ne contiennent aucun code du SDK Adobe DNG, ni de LibRaw ou d’un autre écrivain DNG. Les matrices de couleur sont calculées à partir des chromaticités publiées de sRGB, Display P3 et Adobe RGB (1998). Adobe propose une licence de brevets sans redevance pour les logiciels qui lisent ou écrivent des fichiers DNG. Ce produit l’utilise, et la licence exige la mention ci-dessous.

This product includes DNG technology under license by Adobe.

DNG est une marque d’Adobe Inc. Ce nom sert seulement à désigner le format de fichier.

## Noms et interopérabilité

Les noms de films, scanners, espaces colorimétriques, namespaces XMP et produits identifient des cibles et gardent les fichiers interopérables. Les profils ICC de sortie synthétisés par le moteur Windows portent des libellés descriptifs (`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`) et une mention `CC0 1.0 Universal` afin que les images exportées ne subissent aucune restriction de droit d'auteur liée au profil. Aucune propriété de marque ni affiliation n'est revendiquée. Le périmètre complet est dans [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Contrôles automatiques et ce qu'ils ne couvrent pas

`python3 scripts/ci/verify-provenance.py` échoue sur l'un de ces cas.

- Une ressource fournie non déclarée, ou dont l'empreinte a changé
- Du C/C++/Objective-C, des paquets externes, des archives binaires ou une arborescence vendor dans l'application
- Des noms propres à SANE ou des traces d'une implémentation externe contrôlée dans le code de l'application
- Une modification qui ferait mettre le plugin SANE dans l'application par le script de publication
- Du matériel d'images FILM-R dans le dépôt

Ce contrôle arrête les régressions évidentes de l'arborescence actuelle. Il ne prouve pas la similarité avec l'ensemble d'Internet, ni les droits sur les entrées photographiques ou de profil, ni les brevets, marques ou décisions juridiques nationales. Quand une origine change, revoyez la déclaration avec l'empreinte. Quand c'est flou, sortez la ressource de la distribution et demandez à l'ayant droit ou à un spécialiste.
