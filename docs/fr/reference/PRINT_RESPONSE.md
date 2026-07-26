# Réponse de tirage fixe

[Accueil de la documentation](../README.md)

Où ça se trouve :

- Swift : `PrintResponse` dans `Sources/Chromabase/Film/NegativeInversion.swift`
- Metal : le noyau `negativeInvert`
- Test de verrouillage :
  `NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## La courbe

Une courbe caractéristique de film explique l'exposition face à la densité en trois parties :
pied, partie droite, épaule. negaflow approche l'épaule dans le domaine des densités par une
exponentielle étirée.

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

`A`, `r` et `s` sont les formes courtes de `amplitude`, `rate` et `shape` dans le code.
`d_{\max}` correspond à `dmaxNorm`.

- `D` : densité optique une fois le support retiré
- `d` : cette valeur divisée par la plage de densité utilisée
- `P` : luminosité de sortie linéaire

La courbe monte sur toute la plage. Pour `d ≥ 0`, la sortie tombe dans `[baseToe, ceiling)`. Les
valeurs négatives, comme un rétroéclairage plus lumineux que le support ou les perforations, ne
sont pas ramenées à zéro. Elles continuent en nombres positifs finis.

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

La réciproque a aussi une forme fermée. Elle sert à fabriquer des négatifs synthétiques et à
faire des contrôles aller-retour.

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## Les quatre points d'ancrage

Les coefficients de la courbe ne sont pas stockés. Ils se calculent à partir de ces valeurs.

| Point d'ancrage | Couleur | Noir et blanc | À quoi il sert |
|---|---:|---:|---|
| `P(0)` point noir du support | 0.001 | 0.0005 | Évite de coller au code 0 en 8 bits |
| `P(midFraction)` gris moyen | 0.18 | 0.18 | Gris 18 % |
| `P(1)` blanc | 0.70 | 0.85 | Luminosité de la zone la plus dense mesurée |
| `P(∞)` plafond | 0.90 | 0.98 | Marge pour la lumière réfléchie |

`midFraction` vaut `0.60D / 1.55D`, soit environ `0.387`.

Calcul des coefficients :

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## Plage de densité par défaut

`normalRange` n'est pas la densité maximale physique du film. C'est la plage qu'utilise une
scène normalement exposée. Elle compte surtout quand le support n'a pas pu être mesuré, ou quand
le contraste de la scène est très faible.

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62` : pente approximative de la partie droite sur une courbe C-41
- Couleur `2.5` : environ 7⅓ diaphragmes de luminance diffuse, plus la marge des hautes lumières
- Noir et blanc `3.5` : habitude du tirage noir et blanc, qui utilise une partie droite plus longue
- `0.60D` : densité du gris moyen d'une scène normalement exposée

`applySceneRanged` mesure la plage de densité que l'image utilise réellement, canal par canal,
au lieu de prendre cette valeur.

## Ce qui a changé en v4

L'ancienne approche utilisait une fonction découpée en trois sections et des préréglages fixes.
La v4 utilise une seule courbe et quatre points d'ancrage. Plus de frontières de sections, et
chaque valeur se retrouve dans le code et les tests.

Face à l'ancien résultat :

- Tons moyens et hautes lumières couleur, densité normalisée 0,3 à 1,1 : dans ±0,05 diaph
- Ombres profondes couleur, 0,1 à 0,2 : environ −0,2 diaph
- Point noir du support en couleur : environ +0,25 diaph
- Noir et blanc : ombres environ −0,4 diaph, tons moyens environ +0,1 diaph
- Le point d'ancrage gris moyen 0,18 de NORITSU/FUJI reste

## Sources et périmètre

Pied, partie droite, épaule et gamma viennent de la sensitométrie publiée. Aucun coefficient de
courbe de cette littérature n'a été copié. negaflow calcule les siens à partir des quatre points
d'ancrage ci-dessus.

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [Comparaison de papiers RA-4](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

Les plages de contraste connues des matériaux RA-4 ne sont pas reprises telles quelles. Le
contraste de cette courbe vient du `shape` issu des quatre points d'ancrage.
