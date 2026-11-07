# Chroma Engine

[Accueil de la documentation](../README.md)

Chroma Engine inverse et développe le film. Le code se trouve dans le module `Chromabase`. L'application et la CLI utilisent le même module : une même entrée suit donc le même ordre d'étapes.

| En un coup d'œil | Détail |
|---|---|
| Développement par défaut | `MAIN`, Équilibre auto ON |
| Base du film | Mesure automatique, pipette, saisie directe RVB |
| Couleur interne | Espace colorimétrique linéaire en virgule flottante 32 bits |
| Fonctions automatiques | Équilibre auto ON |
| Espace colorimétrique de sortie | sRGB, Display P3, Adobe RGB, ICC RVB personnalisé |

> [!IMPORTANT]
> Par défaut, la cible est `MAIN` avec Équilibre auto sur ON. L'interrupteur est une petite pastille à droite du titre Cible. Il n'apparaît que pour les négatifs couleur et noir et blanc avec MAIN (y compris PRINT) et CS. Il ajuste la couleur et la luminosité d'après la photo actuelle, et sur OFF cette étape est sautée. Tonalité auto, balance des blancs automatique, niveaux auto et couleur auto restent des fonctions distinctes, désactivées par défaut.

## Ce qui prime

1. Si la base du film peut être mesurée, la mesure l'emporte sur la valeur par défaut choisie d'après le nom.
2. Les propriétés du film, la source lumineuse de numérisation, le style du scanner et la correction automatique de scène sont tenus séparés.
3. Des fonctions comme Tonalité auto et la balance des blancs automatique ne s'activent que lorsque vous les lancez.
4. La même source, les mêmes valeurs de retouche et le même lot de profils suivent le même ordre d'étapes.
5. Les tests synthétiques et la validation sur appareil réel ne sont jamais présentés comme une même preuve.

## Ordre des étapes

L'image de travail est traitée dans un espace colorimétrique linéaire en virgule flottante 32 bits. Seules les opérations qui exigent un gamma se convertissent à leur étape fixe, et l'encodage pour un écran ou un format de fichier vient à la fin.

1. Lire le fichier et corriger l'orientation.
2. Entrée linéaire (RVB d'appareil pour le RAW).
3. Type de film : un positif passe au traitement positif, un négatif voit sa base mesurée.
4. Densité optique et inversion, puis Équilibre auto ON ou OFF, puis la matrice d'appareil du RAW.
5. Cible de développement et profils.
6. Tonalité, couleur et retouche locale.
7. Détail et effets.
8. Espace colorimétrique d'affichage ou de sortie.

Le `CIContext` n'est pas reconstruit à chaque rendu. Il est réutilisé, réparti par usage : affichage, analyse, export. L'aperçu ne calcule que la taille nécessaire et la dernière version de retouche, et l'export refait le rendu à la taille de la source.

Documentation Core Image d'Apple :

- [CIImage](https://developer.apple.com/documentation/coreimage/ciimage)
- [CIContext](https://developer.apple.com/documentation/coreimage/cicontext)
- [workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontext/workingcolorspace)
- [Core Image performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html)

## Base du film

### Pourquoi mesurer

La partie non exposée d'un négatif est un point de référence qui combine le film, le développement et la source lumineuse de numérisation. Le masque orange du négatif couleur s'y trouve aussi. Se tromper de base fausse toutes les densités et relations de canaux qui suivent. Les données Kodak de la Portra 400 consignent aussi séparément la densité minimale, les courbes caractéristiques et la densité spectrale des colorants.

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)

### Mesure automatique

`FilmBaseEstimator` évalue la distribution spatiale des pixels clairs sur toute la vue pour repérer la base non exposée.

- Un pixel de film ne peut pas être plus clair que la base non exposée.
- Tout ce qui est bien plus clair peut être du rétroéclairage, une perforation ou l'extérieur du film.
- Une vraie base tend à former une large bande le long du bord de la vue.
- Avec plusieurs bandes de film sur une planche, les zones séparées peuvent être lues ensemble.
- Une limite où se mêlent porte-film et film est moins fiable que l'intérieur.

Il établit la distribution de luminosité sur une image d'analyse réduite, regroupe les zones connexes, puis écarte les candidats situés hors du film. Quand plusieurs bandes passent les conditions, elles sont calculées ensemble. Le résultat consigne aussi la méthode retenue et sa confiance.

### Choix de la méthode

| Mode | Comportement |
|---|---|
| `Manual` | Utilise le RVB saisi comme Dmin. Une prise réussie à la pipette atterrit ici aussi. |
| `Film` | Utilise la mesure comme Dmin, et le film choisi fournit surtout `dmaxNorm`. Les valeurs par défaut du film et de la source n'interviennent que si la mesure échoue. |
| `Auto` | Utilise l'analyse spatiale et se replie sur la méthode fondée sur les bords en cas d'échec. |

Sans valeur manuelle, ou avec un mauvais identifiant de film, on passe à la méthode sûre suivante. L'objet le plus clair de la scène n'est jamais pris tel quel pour la base du film.

## Densité optique et inversion

La densité vient de la transmittance linéaire `T` et de la base par canal `Dmin` :

```math
D = \log_{10}\left(\frac{D_{\min}}{T}\right)
```

`D = 0` signifie que l'entrée égale la base non exposée. Les perforations ou le rétroéclairage peuvent donner des valeurs négatives. Ces valeurs restent finies et ne sont pas écrêtées sur-le-champ.

### Données par type de film

La table actuelle contient 27 noms de film, couvrant le négatif couleur, le noir et blanc et le négatif cinéma. Ces données servent à :

- La valeur Dmin par défaut quand la base ne peut pas être mesurée
- Des facteurs de densité fixes relatifs au type de film

Certaines valeurs ont été approchées en lisant des courbes dans des documents publics, d'autres fixées prudemment. 27 noms ne font pas 27 profils colorimétriques validés, et une fois la base mesurée, la mesure l'emporte.

### MAIN/PRINT et CS

Avec Équilibre auto ON, chaque canal utilise le centile de 0,2 % le plus dense de la scène, avec une limite de plage de 1,8D, suivi de la courbe `shoulder-print-response-v4` et de la vibrance pour scènes ternes. OFF utilise la même courbe avec une plage nominale fixe (couleur 1,55D, N&B 2,17D). Pour les négatifs couleur, OFF multiplie aussi par un étalonnage de plage par canal propre au scanner et au film, établi sur au moins trois vues de la même bobine.

ON peut modifier la luminosité et la couleur selon le contenu de la scène. Aucun des deux modes n'établit une exactitude mesurée des couleurs du film. Les formules, la limite de 1,8D et l'ordre du RAW sont dans :

[Réponse négative](../reference/PRINT_RESPONSE.md)

## Trois sortes de profils

| Sorte | La question à laquelle elle répond | Valeurs |
|---|---|---|
| Type de film | Quelles sont la base et la plage de densité du film | Dmin/Dmax, type de film |
| Source lumineuse | Comment la source de numérisation a-t-elle influencé chaque canal | Gain par canal, correction pilotée par la base |
| Cible de scanner | Quel style de tonalité et de couleur a le résultat | Statistiques relatives de numérisations faites pour ce projet |

Garder ces trois éléments séparés évite qu'un seul nom de film représente à la fois les propriétés de l'émulsion, la couleur de la source lumineuse et le style de sortie d'un laboratoire. Quand une vraie base existe, la mesure l'emporte sur les valeurs par défaut de la source. Les statistiques de scanner ne sont pas utilisées telles quelles comme matrice de couleur absolue d'une scène.

Les données sont décrites dans [Profils de film](FILM_PROFILES.md).

## Cibles de développement

### `MAIN`

La cible par défaut, avec Équilibre auto sur ON. L'interrupteur est décrit en haut de cette page.

### `PRINT`

L'image de travail est la même que pour `MAIN`. Un profil ICC RVB d'imprimante valide est appliqué une seule fois, à la fin de l'export. Un profil absent ou invalide échoue, au lieu de se rabattre sur du sRGB ou des valeurs de papier arbitraires.

### `HS`, `SP`

Un rendu fixe appliqué après l'inversion. Il ne lit rien dans l'image, donc un pixel donne le même résultat dans toutes les photos. L'exposition et la couleur propres à chaque vue relèvent de l'inversion et des boutons Tonalité auto, Balance des blancs automatique, Niveaux auto et Couleur auto à droite.

Le rendu se compose d'une courbe de tonalité de luminance, d'un gain de saturation qui suit la luminosité et, pour `HS`, d'une légère inclinaison de l'axe des gris. Toutes les courbes sont cubiques monotones : rien ne se plie aux nœuds.

- `SP` provient de quatre vues d'une même bobine numérisées sur un vrai SP-3000 et sur le scanner du projet, appariées pixel par pixel. La courbe de tonalité tient pour un quart de son poids des centiles de 185 vues SP-3000. Sur ces quatre vues, le CIEDE2000 médian par rapport à la numérisation SP-3000 passe d'environ 7,4 pour `MAIN` à 3,9. Une vue sombre bouge à peine, car le laboratoire y a retiré vue par vue une dominante rouge dans les ombres, ce qu'un rendu fixe ne peut pas faire.
- `HS` n'a pas de paires de pixels. Il part de `SP` et ajoute la différence médiane entre les deux machines sur trois bobines dont les noms de film et de bobine concordent : tons moyens un peu plus sombres, blancs un peu plus hauts, pixels colorés à 0,88× de saturation, et gris tirant sur le vert dans la moitié claire (a* d'environ −1 à −4).
- `HS` accentue le canal de luminosité. Le rayon est de 0,9 px à la sortie 35 mm de la machine (3089 px sur le grand côté) et suit la résolution, de sorte que l'aperçu et l'export concordent. L'intensité n'a pas été mesurée.

Choisir un profil fourni ajoute encore `scannerSignature`, la différence relative entre bobines dont les noms et les nombres d'images concordent sur les deux machines. Tous les profils actuels sont `realOnly`.

- La différence relative n'est calculée que si les noms de bobines et les nombres d'images sont assez proches.
- Les valeurs dont le sens s'inverse ne sont pas appliquées.
- En noir et blanc, les composantes de couleur sont écartées.
- Si le SHA-256 d'un fichier ou du manifeste ne concorde pas, tout le lot de profils est refusé.

### `F135`, `HR`

Ce projet n'a aucune numérisation de référence d'un Pakon F-135 ni d'un Kodak HR-500 : aucune des deux cibles n'est donc vérifiée par rapport à sa machine. Les deux partent du rendu `SP` mesuré, auquel s'ajoute la courbe du papier Kodak Endura Premier (fiche E-4070) calée sur son ton moyen. À partir de 1 IL sous le gris moyen et au-dessus, elles partagent cette courbe. Elles diffèrent dans les ombres.

- `F135` suit le papier jusqu'à −2 IL. À partir de −3 IL et en dessous, il reste 0,9 IL sous `SP`, l'écart le plus grand que creusait le pied du papier. Les noirs sont plus profonds que `SP` et chaque IL d'ombre reste séparé : le contraste local y vaut au moins 91 % de celui de `SP`.
- `HR` garde les ombres mesurées de `SP` sous −4 IL. Les points à −3 et −2 IL sont un peu abaissés pour que la courbe monte vers le ton moyen du papier sans creux de contraste. Ses ombres sont jusqu'à 5,4 L* plus claires que celles de `F135`, et la saturation passe à 0,92×.

Les vérifier demande ce qu'avait `SP` : les mêmes négatifs numérisés sur la vraie machine.

### `EXPIRED`

Une cible de récupération pour les vieux films. Elle ne désature pas en bloc et n'étire pas la plage, et reste dans une correction limitée que les preuves actuelles soutiennent.

### `CS`

`CS` (Custom) réunit 18 styles de couleur en trois groupes : Emulsion, Reversal, Dye Transfer, Skip Bleach, Plate Glass, Amber Glass, Ultramarine, Terracotta, Celadon, Nacre et Dichroic (11) ; Wetzlar, Classic, Studio et Rochester (4) ; Slide Show, Cinema et Point & Shoot (3).

Une cible Custom utilise l'inversion `MAIN` avec Équilibre auto, puis applique la réponse custom-3 en tonalité, densité et chroma. Les profils de scanner ne servent pas avec elle. La CLI accepte les mêmes identifiants, par exemple `--target classic`.

## Le rendu film sur une source numérique

L'onglet Film à gauche propose des émulsions de diapositive et de négatif couleur. Pour une numérisation, ce n'est qu'une transformation de couleur, car la numérisation porte déjà dans ses pixels la latitude propre au film, sa réponse de densité, sa diffusion et son grain.

Une photographie numérique n'a rien de tout cela. Une mesure a montré ce que fait une simple transformation de couleur : sur une entrée rendue par l'appareil, les échelons de hautes lumières se sont effondrés à 0,0031, environ un quatorzième des mêmes échelons sur une entrée plate, tandis que la saturation augmentait. Le résultat ressemble à un filtre numérique.

Une source marquée `Digital Color` ou `Digital B&W` suit donc une chaîne distincte qui refait, dans l'ordre, ce que fait le film :

1. Défaire le rendu d'affichage de l'appareil pour estimer l'exposition que le film aurait reçue. Le détail écrêté ne revient pas : c'est une reconstruction plausible.
2. Ajouter diffusion et halation tant que l'image est encore en lumière linéaire, avant toute densité. La lumière qui revient frappe d'abord la couche rouge, ce qui donne un halo à dominante rouge, et redistribue la lumière sans ajouter d'énergie.
3. Développement virtuel. Une courbe caractéristique construit la densité, les coupleurs DIR inhibent les couches voisines, puis un négatif passe par le papier RA-4. Le gamma bas d'un négatif et le gamma élevé du papier sont deux courbes distinctes, ce qui permet aux hautes lumières de s'adoucir sans écrêtage.
4. La signature colorimétrique de l'émulsion, puisque le contraste est déjà venu de l'étape 3.
5. Un grain qui suit la densité, et une réponse des contours tirée de la FTM de la fiche technique.

Les sources numérisées n'entrent jamais dans cette chaîne. L'interrupteur est le seul indicateur de source, et le chemin de numérisation est inchangé.

L'exposition est remise à l'échelle de la latitude de chaque émulsion. Une inversible devient blanche environ une vue au-dessus du gris moyen : y pousser telle quelle une scène numérique de six vues ne laisserait aucun détail dans les hautes lumières. La remise à l'échelle préserve le classement de contraste de chaque émulsion.

Le grain et la halation deviennent des propriétés du film dès qu'une émulsion est choisie : les curseurs de texture en règlent donc l'intensité, au lieu d'ajouter un second effet séparé.

## Commandes de développement

| Groupe | Éléments |
|---|---|
| Tonalité | Exposition, contraste, hautes lumières, ombres, blancs, noirs, courbes de points RVB et par canal |
| Couleur | Température, teinte, vibrance, saturation, TSL à 8 couleurs, étalonnage des couleurs à trois zones, correction par canal, conversion et virage en noir et blanc |
| Détail et effets | Netteté, clarté, correction de la brume, grain de film, vignetage, halation, réduction du bruit |
| Retouche locale | Masques radial, linéaire, polygonal et au pinceau, densité + et − |

Ces valeurs sont enregistrées sous forme d'historique de retouches pas à pas. GrainMend et la retouche locale ordinaire diffèrent par leur but et leur mode de stockage.

### Corrections automatiques

| Commande | Comportement |
|---|---|
| Tonalité auto | Attribue exposition, contraste, densité, hautes lumières, ombres, blancs et noirs. Conserve les commandes de couleur et les courbes de l'utilisateur. |
| Balance des blancs automatique | Estime la température et la teinte à partir de bandes de luminance proches du neutre. Rejette les échantillons dont un canal RVB est écrêté et réduit la correction quand les indices de neutralité sont rares ou couvrent une plage tonale étroite. |
| Niveaux auto | Mesure des extrémités de luminance communes et applique le même gain de luminance au RVB. Préserve les rapports entre canaux au lieu d'étirer chaque canal séparément. |
| Couleur auto | Ajuste les dominantes résiduelles sur des candidats neutres. N'utilise des pentes par canal que lorsqu'un ajustement prédit des bandes de luminance séparées et inutilisées, et sinon des gains. Un indice de repli faible reçoit moins de correction. |

Tonalité auto vérifie la première proposition sur un aperçu rendu. Si elle propose un nouveau changement d'exposition ou de point blanc, elle rend aussi ce candidat et ne l'accepte que si un score portant sur le ton moyen, les extrémités, la plage tonale et l'écrêtage s'améliore. C'est une correction bornée, pas une recherche d'un rendu idéal unique. Répéter la commande attribue les réglages au lieu de les cumuler, et réinitialiser Tonalité auto conserve les commandes de couleur de l'utilisateur.

L'analyse utilise des moyennes pondérées par la surface en RVB linéaire, avec un grand côté borné. La tonalité et la balance des blancs utilisent un aperçu sRGB : l'écrêtage désigne donc l'écrêtage des canaux de l'aperçu, pas la saturation du capteur. Ces estimations ne peuvent pas distinguer toutes les couleurs de sujet d'une dominante de l'éclairage ni établir une exactitude mesurée des couleurs du film. L'Équilibre auto MAIN/CS et sa vibrance pour scènes ternes relèvent de l'étape d'inversion.

## Gestion des couleurs

Si l'entrée porte un ICC valide, cet espace colorimétrique est lu. Le calcul interne se fait dans l'espace de travail linéaire fixe, et le passage à un espace de sortie a lieu à l'affichage, à l'épreuve écran et à l'export.

Principales sorties prises en charge :

- sRGB
- Display P3
- Adobe RGB
- Un ICC RVB d'imprimante ou de sortie choisi par l'utilisateur

Le nom, la taille en octets et le SHA-256 du profil d'imprimante sont figés au début de l'export. Si le fichier change pendant le rendu, l'exécution s'arrête.

Rien n'affirme que le chemin Core Image et ColorSync actuel produit, bit pour bit, la même intention de rendu et la même compensation du point noir sur toutes les versions de macOS. Cette garantie demanderait d'abord un chemin de tampon ColorSync distinct et des contrôles mémoire pour les grandes images 16 bits.

## Encodage de sortie

Les réglages de format sont hors du pipeline couleur, mais ils décident de ce qui subsiste dans le fichier livré.

Le JPEG stocke la couleur à une résolution inférieure à celle de la luminance, sauf si l'encodeur dépasse son seuil de sous-échantillonnage. En dessous, la chrominance est divisée par deux à l'horizontale et à la verticale, ce qui adoucit les contours saturés alors que le détail de luminance reste intact. Une qualité de 95 % ou plus est donc encodée sans sous-échantillonnage de la chrominance, et les réglages plus bas gardent la valeur choisie, car les choisir revient à demander un fichier plus petit. Le PNG et le TIFF sont sans perte et ne sous-échantillonnent jamais. Leur seul réglage de qualité est la profondeur de bits, 8 ou 16 bits par canal, et le tramage n'est appliqué qu'à 8 bits, où il masque les bandes de quantification.

## Performances et sécurité

- Le `CIContext` est réutilisé par usage.
- Les réglages utilisent un aperçu de résolution plus basse, et l'export reconstruit à partir de la source.
- Les tâches longues revérifient l'identifiant de vue, la version de retouche et la session juste avant d'appliquer un résultat.
- Quand la mémoire baisse, les caches comme les vignettes et les aperçus sont abandonnés.
- Originaux et historique des retouches sont tenus à part des caches.

## Niveaux de validation

1. Tests de formules : monotonie de la courbe, ancrages, inverse
2. Images synthétiques : entrée et sortie connues, écrêtage, orientation, espace colorimétrique
3. IT8 synthétique : l'aller-retour mathématique sur 264 plages
4. Statistiques de prises de vue réelles : les profils `realOnly`
5. Paires REAL/TARGET : un contrôle qualité d'appareil avec un matériel de validation distinct
6. Matériel réel : un vrai scanner, un vrai film, un écran et un tirage

Un bon résultat IT8 synthétique ne prouve pas l'exactitude absolue sur de vrais négatifs. Juger la qualité d'un profil de scanner relève de [Contrôle qualité des profils scanner](../reference/PROFILE_QUALITY_GATE.md) et de [Validation colorimétrique IT8](../reference/IT8_COLOR_VALIDATION.md).

## Où se trouve le code

- `Sources/Chromabase/Engine/`
- `Sources/Chromabase/Film/`
- `Sources/Chromabase/Develop/`
- `Sources/Chromabase/Adjustments/`
- `Sources/Chromabase/Profiles/`
- `Sources/Chromabase/Imaging/`
- `Sources/Chromabase/Export/`

La version actuelle du produit est `1.2.6`. Les changements de l'historique des retouches et des schémas de profils devront eux aussi passer par une validation dans les versions suivantes.
