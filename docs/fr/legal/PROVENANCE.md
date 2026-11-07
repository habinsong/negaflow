# Provenance du code et des ressources

[Accueil de la documentation](../README.md)

Ce document consigne le périmètre de distribution sous Apache-2.0 de l'application negaflow. C'est un relevé de provenance pour vérifier le dépôt et les artefacts de publication, pas un avis juridique.

## Code

L'intégration Swift, Python et shell de `negaflow-mac` est écrite pour negaflow.

Le décodage du RAW d'un négatif utilise une révision figée de LibRaw, compilée en `libraw.dylib` remplaçable et distribuée sous CDDL-1.0. Les deux plateformes appliquent les mêmes trois correctifs :

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): dans `src/demosaic/xtrans_demosaic.cpp`, garde les tuiles Fuji X-Trans dans l'ordre, traite en parallèle les lignes à l'intérieur de chaque tuile et exécute la passe des limites du vert par groupes de lignes qui ne se touchent pas
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): dans `src/postprocessing/mem_image.cpp`, copie en parallèle les lignes de la bitmap de sortie
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): dans `src/decoders/decoders_dcraw.cpp`, confie les données JPEG sans perte ordinaires (CR2) et Nikon NEF à des décodeurs de Huffman parallèles et décode en parallèle les lignes Sony ARW2

Les builds corrigés donnent, sur les fichiers RAW testés, le même résultat que le build série non corrigé.

Sous macOS, LLVM OpenMP (libomp 20.1.8, Apache License v2.0 with LLVM Exceptions) est lié statiquement à la bibliothèque. L'application inclut l'archive source, les correctifs, le script de compilation et les fichiers de copyright et de licence dans `Contents/Resources/licenses/libraw/`. `native-preview-bridge.cpp` (Negaflow contributors, CDDL-1.0) contient une sous-classe de LibRaw qui exécute trois boucles par pixel en parallèle avec une sortie identique à l'octet près, et les décodeurs de Huffman parallèles que le correctif de décodeur appelle. Aucun source LibRaw n'est fusionné dans l'arbre source Apache.

Windows utilise la même révision amont et les mêmes correctifs. Son `native-preview-bridge.cpp` (CDDL-1.0) ajoute des fonctions propres à Windows pour les DNG linéaires, et ses autres composants sont consignés dans [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md). Le `CameraNativeRaw.dng` réservé aux tests est un matériel CC0-1.0 de l'entrée 2204 de raw.pixls.us, identifié par le JSON de source voisin, et il est exclu de l'application. Si le fichier de mentions complémentaires est absent, les étapes de compilation et de packaging avertissent et continuent. Les fichiers de licence amont et les sources correspondantes restent inclus.

L'inversion du film repose sur les notions publiées de sensitométrie : densité, pied, partie droite et épaule. Les courbes et coefficients viennent des quatre ancrages photométriques de negaflow, pas des formules ou constantes d'un programme tiers. Les équations et la dérivation sont dans [Réponse négative](../reference/PRINT_RESPONSE.md).

Les fiches techniques publiées des fabricants éclairent trois groupes de constantes de film livrées : les préréglages Dmin et Dmax par type de film (`FilmStockDmin`), les préréglages spectraux et de courbe caractéristique en noir et blanc (`BWFilmProfile`) et les paramètres physiques de grain et de FTM (`DigitalFilmPhysics`). Ces valeurs sont des lectures approximatives ou des ajustements sur des fiches techniques publiées, et `FilmStockDmin` marque chaque entrée `datasheetCurve` ou `estimated` pour que l'origine reste visible. Un chiffre lu sur un graphique publié est un fait sur le film, pas une copie du code ou du texte de quiconque, et une base de film mesurée sur la numérisation l'emporte toujours.

GrainMend IR procède dans cet ordre :

1. Estimer seul le décalage entier entre RVB et IR.
2. Interpoler des moyennes IR tronquées par intervalle de `log(red)` pour construire une courbe de fuite de scène non paramétrique.
3. Soustraire la fuite de scène, puis calculer le contraste relatif par rapport à la moyenne locale.
4. Construire le masque de défauts à partir d'un seuil de bruit local tronqué, de composantes connexes et de l'orientation.

Ce code ne lie ni ne porte la correction IR de SANE. Les articles et pages produit publiés servent de contexte pour confirmer les limites physiques du film et de l'infrarouge. Reprendre une méthode ou un principe est une chose, copier l'expression d'un code en est une autre. Le U.S. Copyright Office trace la même ligne entre méthodes et systèmes et leur expression concrète.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Frontière avec le module SANE

L'application ne contient ni `scanimage`, ni en-têtes SANE, ni configuration de backend, ni code de traitement propre à un appareil. Elle dialogue avec le programme externe installé uniquement par un contrat JSON/NDJSON versionné. Le vrai travail SANE est livré comme dépôt et exécutable GPL-2.0-or-later séparés.

Être un processus séparé ne règle pas à soi seul la question de la licence. La FAQ GNU dit qu'une communication par tube ou ligne de commande ressemble en général à des programmes séparés, mais que la réponse peut changer si la communication est trop intime. Le contrat échange donc des requêtes, des capacités, une progression et des informations de fichiers de résultat indépendantes de l'appareil, et ne partage aucune structure de données SANE.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md)

Le contrôle de publication confirme à nouveau qu'aucun module, exécutable SANE ou bibliothèque SANE ne s'est glissé dans le bundle de l'application. Le côté module livre ses propres `LICENSE`, `COPYING`, sources correspondantes complètes et mentions tierces.

## Ressources fournies

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) fige l'origine déclarée, la licence et le SHA-256 de chaque ressource qui entre dans l'application et l'arbre source.

| Groupe | Origine | Ce qui est livré |
|---|---|---|
| ScannerKit TIFF | Matériel de mise en page photographié et préparé par le mainteneur | 4 fichiers TIFF |
| Icône de l'application | Illustration du projet par le mainteneur | PNG source, PNG de build, ICNS |
| Préréglages de rendu | Valeurs écrites pour negaflow | 6 fichiers JSON |
| Profils de scanner | Construits à partir de mesures de numérisation conservées par le mainteneur | Profils numériques, sans les numérisations sources |

Les métadonnées d'appareil et d'espace colorimétrique visibles dans les fichiers TIFF sont des informations de conteneur issues de la prise de vue et de l'encodage. Le `sourceProfiles` d'un profil de scanner est le chemin logique du matériel de mesure local au moment de la compilation, et ces photographies sources ne sont pas livrées.

Le matériel FILM-R v2 n'est téléchargé que pendant la mesure de qualité. Les images n'entrent jamais dans le dépôt ni dans l'application. La version DOI, CC BY 4.0, les tailles de fichiers et les empreintes sont figées dans [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json).

## Export DNG

Les écrivains DNG (`DNGLinearWriter` dans `negaflow-mac`, `dng_linear_export` dans `negaflow-windows`) sont écrits à partir des numéros de balises et du modèle colorimétrique de la Digital Negative Specification 1.6 publiée par Adobe. Ils ne contiennent aucun code du SDK Adobe DNG ni de LibRaw ou d'un autre écrivain DNG. Les matrices de couleur sont calculées à partir des chromaticités publiées de sRGB, Display P3 et Adobe RGB (1998).

Adobe propose une licence de brevet gratuite pour les logiciels qui lisent ou écrivent des fichiers DNG. Ce produit l'utilise, et la licence exige la mention ci-dessous.

This product includes DNG technology under license by Adobe.

DNG est une marque d'Adobe Inc. Le nom ne sert qu'à désigner le format de fichier.

## Transformation et redressement

La section Transformation et le redressement par ligne sont écrits pour negaflow et ne contiennent aucun code tiers.

- Les segments droits viennent du regroupement des pixels dont la direction du gradient concorde, puis d'une droite ajustée sur l'axe principal de chaque groupe. Regrouper les pixels de contour par orientation est une technique publiée depuis les années 1980.
- Le solveur garde les segments à moins de 30° de la verticale ou de l'horizontale et fait tourner une caméra de focale fixe jusqu'à les rapprocher de la verticale et de l'horizontale autant que le mode le permet. Il minimise avec la méthode du simplexe de Nelder–Mead une somme d'erreurs d'angle où les valeurs aberrantes pèsent moins. Il n'estime ni les paramètres internes de la caméra, ni les directions de Manhattan, ni les points de fuite.
- Le mode Guidé n'utilise que les repères tracés par l'utilisateur.

Adobe détient deux brevets américains en vigueur sur la correction automatique de la perspective des photos. Tous deux ont une date de priorité au 27 avril 2012, et Google Patents prévoit leur expiration en 2033.

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en) revendique l'estimation conjointe d'une matrice de paramètres internes, d'une matrice d'orientation et de points de fuite par optimisation d'une fonction d'énergie. negaflow n'estime aucun de ces éléments.
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en) a des revendications indépendantes plus larges : calculer une homographie ou une transformation plane qui aligne les lignes sur les axes de l'image, en s'appuyant au moins en partie sur des critères de perception humaine. Le solveur de negaflow aligne lui aussi les lignes sur les axes de l'image. L'idée était publique avant 2012. ShiftN, de Marcus Hebel, a été présenté en 2006 et a atteint la version 3.4 en octobre 2008. Il cherchait les bords droits presque verticaux et optimisait une transformation de perspective qui les rendait parallèles et alignés sur le cadre ([ShiftN](https://www.shiftn.de/ShiftN_functionality.html), [historique des versions](https://newsgroup.xnview.com/viewtopic.php?p=57759)). Aucun code de ShiftN n'a été utilisé.

Savoir si une revendication couvre une implémentation donnée est une question juridique, et ce document ne la tranche pas.

## Noms et interopérabilité

Les noms de films, de scanners, d'espaces colorimétriques, d'espaces de noms XMP et de produits servent à désigner les cibles et à garder les fichiers interopérables. Les profils ICC de sortie synthétisés par le moteur Windows utilisent des libellés descriptifs (`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`) et une dédicace `CC0 1.0 Universal`, de sorte que les images exportées des utilisateurs ne portent aucune restriction de droit d'auteur sur le profil. Aucune propriété de marque ni affiliation n'est revendiquée. Le périmètre complet est dans [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Contrôles automatiques et ce qu'ils manquent

`python3 scripts/ci/verify-provenance.py` (à lancer depuis `negaflow-mac/`) échoue dans chacun de ces cas :

- Une ressource fournie qui n'est pas enregistrée ou dont l'empreinte a changé
- Du C/C++/Objective-C, des paquets externes, des archives binaires ou un arbre vendor dans l'application
- Des noms propres à SANE ou des traces d'une implémentation externe contrôlée dans le code de l'application
- Une modification qui amènerait le script de publication à mettre le module SANE dans l'application
- Du matériel d'images FILM-R dans le dépôt

Le contrôle arrête les régressions évidentes de l'arbre actuel. Il ne prouve ni l'absence de ressemblance avec tout l'internet, ni les droits sur des entrées photographiques ou de profils, ni les brevets, les marques ou une issue juridique dans un pays quelconque. Quand une origine change, revoyez la déclaration avec l'empreinte. En cas de doute, retirez la ressource de la publication et interrogez le titulaire des droits ou un spécialiste.
