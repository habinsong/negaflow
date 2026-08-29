# Films que GrainMend IR doit éviter

[Accueil de la documentation](../README.md)

Le nettoyage infrarouge lit l'image visible et l'image infrarouge séparément, puis les superpose
pour trouver les défauts.
Cette méthode ne convient pas à tous les films.

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

Ce qui décide ici n'est pas que le film soit négatif ou positif, mais **ce qui forme l'image**.
Le film couleur blanchit son argent au traitement et ne garde que des colorants, transparents à
l'infrarouge. Le film noir et blanc est une image argentique qui bloque l'infrarouge : la correction
lirait la photographie elle-même comme un immense défaut et l'effacerait.

| Type de film | IR automatique | Pourquoi |
|---|---|---|
| Négatif couleur | Sous conditions | Image de colorants. Le plugin doit signaler l'IR et passer le contrôle d'alignement |
| Positif couleur | Sous conditions | Image de colorants. Mêmes conditions que le négatif couleur |
| Négatif et positif noir et blanc | Non | L'image argentique bloque l'infrarouge |

`FilmType` ne sépare pas un noir et blanc chromogène d'un argentique et ne distingue pas un
Kodachrome d'une diapositive courante : deux cas restent donc à l'appréciation de l'utilisateur.

- Un noir et blanc chromogène est numérisé comme du noir et blanc ; l'IR reste donc désactivé même
  si le film le permettrait. Rien n'est deviné à partir du seul type de film.
- Kodachrome est une diapositive couleur, l'IR est donc proposé. Ses colorants atténuent l'infrarouge
  autrement que l'E-6, ce qui peut sous- ou sur-corriger un défaut. Désactivez le calque si le
  résultat semble faux.

## Contrôle d'alignement

`InfraredDefectRemoval` compare la texture de fuite de l'IR au canal rouge du RVB et cherche un
décalage entier.
Le résultat porte `AlignmentDiagnostics`.

| État | Signification |
|---|---|
| `notRequested` | L'appelant a indiqué que les deux plans coïncident déjà |
| `aligned` | La corrélation passe le seuil et l'optimum est dans la plage de recherche |
| `insufficientTexture` | L'IR manque d'indices d'alignement |
| `weakCorrelation` | La corrélation ne passe pas le seuil |
| `searchLimitReached` | L'optimum est sur la limite de recherche |

Les trois derniers ne sont pas remplacés par `(0,0)`.
Le traitement s'arrête sur une erreur `alignmentUnreliable`.
Si l'optimum tombe sur la limite de recherche, c'est un échec quelle que soit l'amplitude du
décalage.

Les tests automatisés ne remplacent pas l'alignement RVB/IR sur un appareil réel ni les résultats
film par film.
Les contrôles sur scanner réel se font à la main, sur de la vraie pellicule.

Le pilotage des périphériques SANE et le code de capture ne vivent que dans le dépôt séparé
`negaflow-scanner-sane`.
