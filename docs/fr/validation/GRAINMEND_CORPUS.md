# Comparaison GrainMend sur scans réels

[Accueil de la documentation](../README.md)

Les contrôles de régression de GrainMend RGB utilisent FILM-R v2.

| Élément | Valeur |
|---|---|
| Fichiers endommagés et restaurés à la main | 44 de chaque |
| Licence | CC BY 4.0 |
| Taille totale | 437 570 872 octets |
| Emplacement | `build/defect-corpus/` |
| Sert à | Comparaison de régression GrainMend RGB |

## Le matériel

- Titre : *Authentically damaged & manually restored film scans*
- Autrice : Daniela Ivanova
- DOI : <https://doi.org/10.6084/m9.figshare.21803304.v2>
- Article : <https://doi.org/10.1111/cgf.14749>
- Description : <https://daniela997.github.io/FilmDamageSimulator/>
- Licence : CC BY 4.0
- Contenu : 44 scans de film 35 mm endommagés et 44 restaurations manuelles d'expert
- Taille totale : 437 570 872 octets

Les images restent hors du dépôt.
`Config/defect-corpus-film-r-v2.json` fige la version DOI, la licence, le nombre de paires et la
taille totale.
Le script de récupération contrôle le MD5 et la taille de chaque fichier fournis par Figshare.
Les téléchargements et les résultats vont dans `build/defect-corpus/`, que Git ignore.

## Récupération

La commande simple récupère une paire, pour un coup d'œil rapide.

<details>
<summary>Commandes de récupération</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

Les 44 paires :

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

Si le CDN de fichiers de Figshare bloque les requêtes automatiques, téléchargez le ZIP depuis la
page du jeu de données avec `Download all` et vérifiez-le tel quel.
L'extraction n'aboutit que si les noms de fichiers, les tailles et les MD5 Figshare du ZIP
correspondent tous au contrat figé.

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

Un seul cas :

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## Lancer la comparaison

Placez les fichiers endommagés et les restaurations, dont le nom se termine par `_restored`, dans le
même dossier.

<details open>
<summary>Commande pour les 44 paires</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only` n'écrit pas les gros PNG.
Sans cette option, il produit aussi `before`, `after`, `diff`, `mask` et des recadrages à 100 % pour
la vérification manuelle.

Ce que porte le rapport :

- Nombre de détections, confiance, nombre de pixels modifiés, temps de traitement
- PSNR et erreur absolue moyenne entre le fichier endommagé et la restauration d'expert
- PSNR et erreur absolue moyenne entre le résultat GrainMend et la restauration d'expert
- Variation de PSNR
- Part des pixels dont l'erreur face à la référence baisse ou monte

L'article FILM-R utilise PSNR, SSIM et LPIPS ensemble.
Ce dépôt n'ajoute pas de dépendance ML, donc il ne calcule que le PSNR et l'erreur absolue avec la
bibliothèque standard.

Ces chiffres seuls n'approuvent pas une publication.
Les restaurations manuelles portent aussi des choix d'édition et des écarts JPEG.
Le plancher de qualité automatique pour rejouer le même matériel avec les mêmes réglages est figé
dans `Config/defect-removal-film-r-v2-baseline.json`.
La décision finale demande de regarder `before`, `after`, `diff`, `mask` et les recadrages à 100 %
côte à côte.

> [!CAUTION]
> La qualité d'image de GrainMend ne s'approuve pas sur le seul PSNR ou la seule erreur moyenne.
> L'atteinte à la texture réelle et les fausses détections se jugent avec les images avant et
> après, l'image de différence, le masque et les recadrages à 100 %.

Ce matériel ne vérifie que le chemin GrainMend RGB sur des images rendues.
Il ne prouve ni le décodage RAW, ni l'exactitude de l'inversion du film, ni l'alignement IR, ni le
comportement d'un scanner réel.

## Résultat du 2026-07-25

Les 44 paires ont tourné sur un build Release avec `--metrics-only --crops 0`.
L'ancienne référence de régression à sensibilité 3.0 a été comparée à 0.7, le chemin automatique de
la version publiée.

| Métrique | Ancienne référence 3.0 | Auto sûr 0.7 |
|---|---:|---:|
| Images évaluées | 44 | 44 |
| PSNR meilleur / moins bon / identique | 11 / 33 / 0 | 34 / 6 / 4 |
| Variation moyenne de PSNR | -1,688 dB | +0,466 dB |
| Variation médiane de PSNR | -0,237 dB | +0,118 dB |
| Pire variation de PSNR | -18,952 dB | -1,338 dB |
| Pixels améliorés pondérés | 0,128 % | 0,029 % |
| Pixels dégradés pondérés | 0,792 % | 0,017 % |
| Pixels modifiés pondérés | 0,794 % | 0,043 % |
| Arrêt de sécurité automatique | aucun | 3 images |

L'ancienne valeur par défaut de l'application était 6.0, plus agressive encore que la référence 3.0.
Le chemin automatique de la version publiée descend à 0.7, et la détection des micro-taches est
désactivée par défaut.
Quand les candidats dépassent 2 % d'une tuile, les composantes qui la touchent sont écartées.
Si une tuile dépasse 5 %, ou si le total des candidats après filtrage dépasse 0,06 %, la réparation
automatique n'est pas appliquée à cette photo.
L'utilisateur peut alors resserrer la zone avec le mode Guidé.

Cette limite de sécurité ne concerne que le mode Auto.
Elle ne restreint ni la plage de détection ni la réparation en mode Guidé, Pinceau, Tampon de
duplication ou IR.

`Config/defect-removal-film-r-v2-baseline.json` contrôle la référence de régression observée ainsi
que ces planchers absolus.

- Au moins 30 images améliorées, au plus 10 dégradées
- Variation moyenne et médiane de PSNR à 0 dB ou mieux
- Pire variation de PSNR à -1,5 dB ou mieux
- Pixels dégradés pondérés à 0,03 % au plus
- Pixels modifiés au total à 0,06 % au plus

Face à l'ancienne référence, ce passage améliore 23 images de plus, en dégrade 27 de moins, et
relève le pire cas de 17,614 dB.
Six images restent malgré tout en dessous de la restauration d'expert en PSNR.
FILM-R fournit des dommages réels et des restaurations manuelles, et porte aussi l'ambiguïté du
jugement de restauration.
Le matériel et l'article sont sur
[le projet FILM-R](https://daniela997.github.io/FilmDamageSimulator/) et
[l'article FILM-R](https://arxiv.org/abs/2302.10004).

Écarter les candidats denses du mode Auto rejoint les travaux antérieurs de restauration d'image sur
la réduction des fausses détections dans les zones texturées.
Cela dit, ce résultat ne permet d'affirmer aucun des points suivants.

- Le résultat automatique dépasse la restauration manuelle sur toutes les photos.
- GrainMend RGB équivaut au nettoyage IR matériel.
- L'alignement RVB/IR et la qualité optique d'un scanner réel sont vérifiés.

La reprise complète se lance dans le workflow manuel `GrainMend corpus`.
En plus du contrôle qualité automatique, les recadrages à 100 % demandent un examen manuel.
