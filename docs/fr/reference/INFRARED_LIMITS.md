# Films que GrainMend IR doit éviter

[Accueil de la documentation](../README.md)

Le nettoyage infrarouge lit séparément l'image visible et l'image infrarouge, puis les superpose pour trouver les défauts. Il ne convient pas à tous les films.

- Les films couleur ordinaires et les films noir et blanc à base de colorants peuvent utiliser l'IR.
- Le noir et blanc ordinaire garde son argent, qui bloque l'IR et peut produire une carte de défauts fausse.
- Kodachrome atténue l'IR autrement que les autres films couleur : la correction peut être insuffisante ou excessive.

Sources :

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> Si la nature du film ne peut pas être confirmée, l'IR n'est pas appliqué automatiquement. Un mauvais masque IR peut effacer comme défaut une vraie structure de l'image.

## Où l'application est automatique

Ce qui décide, c'est la matière qui forme l'image. Un film couleur ne garde que les colorants après traitement, et les colorants sont transparents à l'infrarouge. Un film noir et blanc est une image d'argent et bloque l'infrarouge : la correction lirait la photo elle-même comme un grand défaut et l'effacerait.

| Type de film | IR automatique | Raison |
|---|---|---|
| Négatif couleur | Conditionnel | Image de colorants. Le module doit signaler l'IR et la confirmation locale dans le canal rouge (`>= 4σ`) ainsi que le plafond de couverture (`<= 5 %`) doivent réussir |
| Positif couleur | Conditionnel | Image de colorants. Mêmes conditions que le négatif couleur |
| Négatif et positif noir et blanc | Désactivé | L'image d'argent bloque l'infrarouge |

`FilmType` ne sépare ni le noir et blanc à colorants du noir et blanc argentique, ni Kodachrome d'une diapositive ordinaire. Deux cas sont laissés à l'utilisateur :

- Le noir et blanc à colorants est numérisé en noir et blanc : l'IR reste désactivé bien que le film le permette. Rien n'est deviné d'après le seul type de film.
- Kodachrome est une diapositive couleur, donc l'IR est proposé. Ses colorants atténuent l'infrarouge autrement qu'en E-6, ce qui peut laisser un défaut sous- ou surcorrigé. Désactivez le calque si le résultat paraît faux.

## Contrôle d'alignement

`InfraredDefectRemoval` associe d'abord les points de défaut IR aux zones sombres locales du canal rouge RVB, et ne recourt à la corrélation entre la texture de fuite IR passe-haut et le canal rouge que lorsque les indices de défaut manquent. Le résultat global porte des `AlignmentDiagnostics` et sert de point de départ avant l'affinage local du décalage de chaque défaut dans le canal rouge.

| État | Signification |
|---|---|
| `notRequested` | L'appelant indique que les deux plans coïncident déjà |
| `aligned` | La corrélation dépasse le seuil et le meilleur point est dans la plage de recherche |
| `insufficientTexture` | L'IR offre trop peu de repères d'alignement |
| `weakCorrelation` | La corrélation n'atteint pas le seuil |
| `searchLimitReached` | Le meilleur point est sur la limite de recherche |

Lorsque le point de départ global renvoie l'un des trois derniers états, la détection ne s'arrête pas aussitôt : elle part de `(0,0)`, vote un décalage grossier consensuel à partir des candidats IR marqués, et exige que chaque défaut candidat passe la confirmation locale dans le canal rouge visible (`>= 4σ`) et le plafond de couverture (`5 %` par défaut), en s'arrêtant avec `noDefects` ou `coverageTooHigh` en cas d'échec.

Les tests automatiques ne remplacent pas la vérification de l'alignement RVB/IR sur un vrai appareil, film par film. Cette vérification se fait à la main, sur de vrais films.

Le code de contrôle et de capture des appareils SANE n'existe que dans le dépôt séparé `negaflow-scanner-sane`.
