# Mesure de GrainMend IR sur scans réels

[Accueil de la documentation](../README.md)

Ce que GrainMend IR retire réellement d'un défaut, mesuré sur des scans réels et non sur des
images de test synthétiques.

| Élément | Valeur |
|---|---|
| Matériel | Epson GT-X900, négatif couleur, 2400 ppp, 16 bits |
| Paires | 5 (scan principal et passe infrarouge) |
| Défauts notés | 140 à 338 par vue |
| Mesuré le | 2026-08-11 |

## Comment la note est établie

Le détecteur ne se note pas lui-même. Un défaut ne compte que si la photographie le
confirme : le candidat infrarouge est mis en correspondance avec la marque sombre du canal
rouge selon son propre décalage local, et il n'est retenu que si ce pic dépasse de quatre
sigma le bruit environnant. Le taux de retrait est l'excès de densité logarithmique au
centre du défaut par rapport à une ligne de base annulaire, avant et après correction. La
surcorrection est ce même nombre devenu négatif : le centre est ressorti plus clair que son
entourage.

## L'acquisition d'abord

La passe infrarouge doit porter la même table gamma et la même mise au point que le scan
principal. Laissée aux valeurs par défaut de l'appareil, la base du film est écrêtée côté
blanc, 9,07 pour cent de la vue bloqués à 65535, et la ligne de base qui sert à mesurer la
profondeur des défauts disparaît. Avec les deux passes réglées à l'identique, l'écrêtage
est nul. Les mesures antérieures à cette correction ne disent rien du détecteur.

## Résultat

| Vue | Candidats vers confirmés | Gain | Retrait au centre | Surcorrection légère/moyenne/grave |
|---|---|---|---|---|
| 19 | 483 vers 262 | 1,12 | 90% | 5 / 0 / 0 |
| 20 | 726 vers 407 | 1,84 | 85% | 16 / 8 / 3 |
| 21 | 1138 vers 494 | 1,52 | 96% | 24 / 5 / 0 |
| 22 | 969 vers 674 | 1,26 | 93% | 25 / 3 / 3 |
| 23 | 540 vers 341 | 1,32 | 95% | 13 / 2 / 0 |

Le gain est le rapport mesuré entre densité visible et densité infrarouge. L'occlusion est
presque plate selon la longueur d'onde : une valeur proche de un indique donc que les deux
passes s'accordent sur ce qui était masqué. Légère signifie un centre 1 à 3 pour cent plus
clair que son entourage, sous le grain du film ; grave signifie plus de 6 pour cent. La
détection prend 0,6 à 0,9 seconde par vue et l'application de la correction 0,1 à 0,3 de
plus.

De 96 à 99 pour cent de la correction tombe à moins de huit pixels d'un vrai défaut
infrarouge, et la correction moyenne par décile de rouge ne montre aucune tendance : la
détection élargie ne déborde donc pas sur la scène.

## Par taille de défaut

Les poussières larges survivaient alors que les rayures partaient proprement. Quatre étapes
ne se trompaient que sur les défauts de plus de quelques pixels, et une cinquième retenait
chaque défaut d'une quantité constante.

| Rayon du petit côté | Avant | Après |
|---|---|---|
| 1 à 2 px | 52 à 74% | 77 à 95% |
| 3 à 4 px | 77 à 89% | 93 à 99% |
| 5 à 7 px | 0 à 91% | 24 à 99% |
| 12 à 17 px | 0 à 73% | 58 à 89% |
| 18 px et plus | 0% | 73 à 93% |

- L'élément structurant de la ligne de base grandissait selon ce que la première passe
  observait, mais cette observation se fait avec la même ligne de base : un défaut plus
  large que l'élément mesure son propre intérieur et paraît petit. Il est désormais
  dimensionné à partir de la résolution.
- Le seuil des candidats est la significativité d'un seul pixel, si bien qu'une poussière
  pâle et large ne franchissait aucun pixel. La même significativité s'applique maintenant
  à la surface couverte.
- La distribution nulle venait de tout le plan de recherche : un défaut aussi grand que ce
  plan devenait sa propre référence et divisait par deux le gain mesuré.
- La quantité à restituer était mesurée depuis la ligne d'appartenance à trois sigma et non
  depuis le plancher propre du film, ce qui laissait cet écart sur chaque défaut.
- Le biais vers le haut d'un pic retenu parce qu'il était grand valait un sigma fixe. C'est
  le rapport de Mills inverse du seuil à quatre sigma : prudence entière au seuil, plus rien
  au-delà de huit.

## Non vérifié

- Aucun contrôle visuel des vues corrigées. La surcorrection légère est ici un nombre, pas
  un jugement sur le rendu.
- Aucun lot complet de dix-huit vues passé dans l'application.
- La vue 20 reste plus basse que les autres, à 85 pour cent. Sa densité infrarouge tourne
  autour de 60 pour cent de celle des autres vues : l'entrée elle-même est probablement
  mince.
- Un seul scanner. V800, V850 et Coolscan n'ont pas été mesurés.
- Les scans couleur 16 bits en basse résolution sortent noirs à 300 ppp et en dessous.
  2400 ppp est normal et aucun effet produit n'est confirmé, mais la cause reste inconnue.
