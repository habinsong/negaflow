# Provenance du code et des ressources

[Accueil de la documentation](../README.md)

On note ici le périmètre de distribution Apache-2.0 de l'application negaflow.
Ce n'est pas un avis juridique.
C'est un relevé de provenance, pour pouvoir revérifier le dépôt et les artefacts de publication.

## Code

`Sources`, `Tests` et `scripts` sont du code Swift, Python et shell écrit pour negaflow.
L'application n'a pas de source C/C++/Objective-C, pas de paquet externe, pas de bibliothèque
statique ou dynamique, pas d'arborescence vendorisée.
Seuls les frameworks système livrés par Apple avec macOS sont liés.

L'inversion du film reprend les notions publiées de sensitométrie : densité, pied, partie droite,
épaule.
Les courbes et les coefficients viennent des quatre points d'ancrage photométriques de negaflow, pas
des formules ou constantes d'un programme tiers.
Les équations et la dérivation sont dans [réponse de tirage fixe](../reference/PRINT_RESPONSE.md).

GrainMend IR procède dans cet ordre.

1. Estimer seul le décalage entier entre RVB et IR.
2. Interpoler des moyennes IR tronquées par intervalle de `log(red)` pour obtenir une courbe non paramétrique de fuite de scène.
3. Soustraire la fuite de scène, puis calculer le contraste relatif à la moyenne locale.
4. Construire le masque de défauts à partir d'un seuil de bruit local tronqué, des composantes connexes et de l'orientation.

Ce code ne lie ni ne porte la correction IR de SANE.
La littérature publiée et les pages produit servent de contexte pour confirmer les limites physiques
du film et de l'infrarouge.
Reprendre une méthode ou un principe est une chose, copier l'expression du code en est une autre.
Le U.S.
Copyright Office trace la même limite entre méthodes et systèmes et leur expression concrète.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Frontière du plugin SANE

L'application n'a pas de `scanimage`, pas d'en-têtes SANE, pas de configuration de backend, pas de
code de traitement propre à un appareil.
Elle parle au programme externe installé uniquement par un contrat JSON/NDJSON versionné. Le vrai
travail SANE est publié dans un dépôt et un exécutable séparés sous GPL-2.0-or-later.

Être un processus séparé ne règle pas à soi seul la question de licence.
La FAQ GNU dit qu'une communication par tube ou ligne de commande ressemble en général à des
programmes distincts, mais que la réponse peut changer si la communication est trop intime.
Le contrat n'échange donc que des requêtes indépendantes de l'appareil, des capacités, une
progression et des informations de fichier de résultat, sans partager de structures de données SANE.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Architecture des plugins scanner](../architecture/SCANNER_PLUGINS.md)

Le contrôle de publication reconfirme qu'aucun plugin, exécutable SANE ou bibliothèque ne s'est
glissé dans le bundle.
Le plugin livre de son côté ses propres `LICENSE`, `COPYING`, le code source correspondant complet
et les avis tiers.

## Ressources fournies

[`Config/bundled-resource-provenance-v1.json`](../../../Config/bundled-resource-provenance-v1.json)
fige l'origine déclarée, la licence et le SHA-256 de chaque ressource qui entre dans l'application
et l'arborescence source.

| Ensemble | Origine | Ce qui est livré |
|---|---|---|
| TIFF ScannerKit | Matériel de mise en page photographié et préparé par le mainteneur | 4 fichiers TIFF |
| Icône de l'application | Illustration du projet, fournie par le mainteneur | PNG source, PNG de build, ICNS |
| Préréglages de rendu | Valeurs écrites pour negaflow | 6 fichiers JSON |
| Profils de scanner | Construits à partir de mesures de scan conservées par le mainteneur | Profils numériques, sans les scans sources |

Les métadonnées d'appareil et d'espace colorimétrique visibles dans les TIFF sont des informations
de conteneur issues de la prise de vue et de l'encodage.
Le champ `sourceProfiles` d'un profil de scanner est le chemin logique du matériel de mesure local
au moment de la construction, et ces photographies sources ne sont pas livrées.

Le matériel FILM-R v2 n'est téléchargé que pendant la mesure de qualité. Les images n'entrent ni
dans le dépôt ni dans l'application.
La version DOI, la licence CC BY 4.0, les tailles de fichiers et les empreintes sont figées dans
[`Config/defect-corpus-film-r-v2.json`](../../../Config/defect-corpus-film-r-v2.json).

## Noms et interopérabilité

Les noms de films, scanners, espaces colorimétriques, namespaces XMP et produits identifient des
cibles et gardent les fichiers interopérables.
Aucune propriété de marque ni affiliation n'est revendiquée.
Le périmètre complet est dans [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Contrôles automatiques et ce qu'ils ne couvrent pas

`python3 scripts/ci/verify-provenance.py` échoue sur l'un de ces cas.

- Une ressource fournie non déclarée, ou dont l'empreinte a changé
- Du C/C++/Objective-C, des paquets externes, des archives binaires ou une arborescence vendor dans l'application
- Des noms propres à SANE ou des traces d'une implémentation externe contrôlée dans le code de l'application
- Une modification qui ferait mettre le plugin SANE dans l'application par le script de publication
- Du matériel d'images FILM-R dans le dépôt

Ce contrôle arrête les régressions évidentes de l'arborescence actuelle.
Il ne prouve pas la similarité avec l'ensemble d'Internet, ni les droits sur les entrées
photographiques ou de profil, ni les brevets, marques ou décisions juridiques nationales.
Quand une origine change, revoyez la déclaration avec l'empreinte.
Quand c'est flou, sortez la ressource de la distribution et demandez à l'ayant droit ou à un
spécialiste.
