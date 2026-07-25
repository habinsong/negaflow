# Films que GrainMend IR doit éviter

[Accueil de la documentation](../README.md)

Le nettoyage infrarouge lit l'image visible et l'image infrarouge séparément, puis les
superpose pour trouver les défauts. Cette méthode ne convient pas à tous les films.

- Les films couleur courants et les films noir et blanc chromogènes acceptent l'IR.
- Les films noir et blanc ordinaires gardent leur argent, qui bloque l'IR et fausse la carte des défauts.
- Le Kodachrome atténue l'IR autrement que les autres films couleur : la correction peut manquer ou déborder.

Justification :

- [Notes techniques et limites Epson](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Tableau des types de film Epson](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast sur le noir et blanc et le Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> Quand la matière du film ne peut pas être confirmée, l'IR n'est pas appliqué automatiquement.
> Un masque IR erroné efface une structure réelle de l'image comme s'il s'agissait d'un défaut.

## Où il s'applique automatiquement

`FilmType` distingue seulement couleur et noir et blanc, négatif et positif. Rien n'y sépare un
noir et blanc chromogène d'un argentique, ni une diapositive courante d'un Kodachrome.

| Type de film | IR automatique | Pourquoi |
|---|---|---|
| Négatif couleur | Sous conditions | Le plugin doit signaler l'IR et passer le contrôle d'alignement |
| Positif couleur | Non | Impossible de savoir s'il s'agit de Kodachrome |
| Négatif et positif noir et blanc | Non | Chromogène et argentique sont indiscernables |

Cela ne veut pas dire que l'IR est impossible sur un noir et blanc chromogène ou une
diapositive couleur courante. Les données actuelles ne confirment pas la matière du film, alors
rien n'est deviné.

## Contrôle d'alignement

`InfraredDefectRemoval` compare la texture de fuite de l'IR au canal rouge du RVB et cherche un
décalage entier. Le résultat porte `AlignmentDiagnostics`.

| État | Signification |
|---|---|
| `notRequested` | L'appelant a indiqué que les deux plans coïncident déjà |
| `aligned` | La corrélation passe le seuil et l'optimum est dans la plage de recherche |
| `insufficientTexture` | L'IR manque d'indices d'alignement |
| `weakCorrelation` | La corrélation ne passe pas le seuil |
| `searchLimitReached` | L'optimum est sur la limite de recherche |

Les trois derniers ne sont pas remplacés par `(0,0)`. Le traitement s'arrête sur une erreur
`alignmentUnreliable`. Si l'optimum tombe sur la limite de recherche, c'est un échec quelle que
soit l'amplitude du décalage.

Les tests automatisés ne remplacent pas l'alignement RVB/IR sur un appareil réel ni les
résultats film par film. Les contrôles sur scanner réel suivent les points IR de la
[checklist QA sur matériel réel](../validation/REAL_QA_CHECKLIST.md).

Le pilotage des périphériques SANE et le code de capture ne vivent que dans le dépôt séparé
`negaflow-scanner-sane`.
