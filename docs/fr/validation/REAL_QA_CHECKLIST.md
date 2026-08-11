# Checklist QA sur matériel réel

[Accueil de la documentation](../README.md)

Voici les points que les tests automatisés et les builds ne peuvent pas confirmer.
Le rendu final à l'écran et le matériel réel sont vérifiés par l'utilisateur.
Une version candidate n'est approuvée que si chaque point requis applicable a un résultat et sa
preuve.

Notez chaque résultat comme `PASS`, `FAIL`, `BLOCKED` ou `N/A`.
`FAIL`, `BLOCKED` et `N/A` demandent une raison.

> [!IMPORTANT]
> Un build dont ce tableau n'est pas rempli n'est pas marqué comme vérifié pour le matériel réel,
> la qualité d'image finale, la signature ou la notarisation. Des tests automatisés réussis ne
> remplacent pas cette vérification.

## Fiche d'exécution

- Version candidate :
- Version et build de l'application :
- Commit ou copie du source :
- Version de macOS :
- Modèle de Mac, architecture, mémoire :
- Écran, facteur d'échelle, état HDR :
- Version du plugin scanner :
- Modèle de scanner et connexion :
- Vérifié par :
- Date :

## 1. Installation et premier lancement

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | La somme de contrôle du ZIP/DMG correspond à la valeur publiée. |  |
|  | Sur un compte utilisateur vierge, il se copie dans `/Applications` et se lance. |  |
|  | Gatekeeper affiche le signataire et l'état de notarisation attendus. |  |
|  | Le premier lancement ne crée que les données décrites dans la documentation. |  |
|  | Sans plugin scanner, aucun appareil ni aucune capacité factice ne s'active. |  |
|  | Informations, version, build, licence et aide sont justes. |  |
|  | À propos affiche la phrase localisée du bicentenaire de Niépce en gras entre « negaflow » et la version `1.0.6`. |  |

## 2. Import, développement, export

Utilisez au moins un JPEG, un TIFF, un DNG/RAW que le décodeur actuel lit, et un fichier haute
résolution.
Notez le SHA-256 de la source avant et après l'exécution.

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Les octets de la source sont identiques avant et après l'import. |  |
|  | L'avertissement d'import en double et ses options se comprennent facilement. |  |
|  | L'état de départ est la correction manuelle avec la cible `main`. |  |
|  | L’import affiche barre de progression, pourcentage et nombre terminé/total ; aucune photo n’est développée automatiquement si la valeur enregistrée est désactivée. |  |
|  | Appliquer au dossier retraite aussi les photos déjà développées et affiche le nombre terminé/total. |  |
|  | Coller des réglages sur une sélection multiple applique procédé, cible, recadrage, rotation, miroir, tonalité, couleur et détail à chaque photo. |  |
|  | Les vignettes numérisées négatif couleur, diapositive, négatif N&B et positif N&B sont développées dans Développement et Tirage. |  |
|  | Le profil de sortie imprimante touche toutes les cases répétées ou mixtes et la page exportée, jamais l’aperçu Développement. |  |
|  | Les sept mises en page s’affichent correctement ; avec plusieurs photos, Image unique, Cyanotype, Plaque de verre et Gélatino-argentique créent une page verticale par photo. |  |
|  | Avec 39 photos, Export et Exportation rapide affichent et écrivent selon le cas 1 page contact, 10 pages à quatre images, 1 page personnalisée par défaut ou 39 fichiers individuels. |  |
|  | Recadrage, orientation, tonalité, couleur, détail, correction locale et annulation fonctionnent. |  |
|  | La comparaison original/développé et l'affichage d'écrêtage correspondent à l'export. |  |
|  | JPEG et TIFF 16 bits s'ouvrent, et leurs métadonnées sont justes. |  |
|  | Conflits de noms, annulation, échec et reprise ne laissent jamais une partie des fichiers marquée réussie. |  |
|  | Sans l'historique d'édition ou le cache requis, une erreur remonte au lieu d'exporter la source. |  |

## 3. Catalogue, sauvegarde, originaux hors ligne

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Au relancement, images, sélection, films et collections, notes et retouches reviennent. |  |
|  | Une sauvegarde interrompue laisse quand même le dernier catalogue sain et sa sauvegarde. |  |
|  | Un catalogue absent ou cassé s'arrête sur l'écran de récupération au lieu de s'ouvrir vide. |  |
|  | Créer une sauvegarde, prévisualiser une restauration, restaurer et relancer fonctionnent. |  |
|  | Les originaux hors ligne sont clairement signalés, et la source n'est pas exportée à leur place. |  |
|  | Le bon original se relie de nouveau et un autre fichier est refusé. |  |
|  | Retirer de la bibliothèque n'efface pas l'original. |  |
|  | Mettre à la corbeille est une action choisie, et reste sans ambiguïté avec des copies virtuelles. |  |
|  | Un dossier replié le reste après la création d’un dossier et après le relancement. |  |
|  | Tous les dossiers amovibles affichent la même action X, qui conserve l’original. |  |
|  | Le glisser-déposer fonctionne entre dossiers importés, créés par l’app et issus du scanner ; un conflit de nom reçoit un nouveau nom sûr. |  |
|  | Les déplacements, renommages et ajouts/suppressions directs dans le Finder apparaissent sans réanalyser toute la bibliothèque. |  |

## 4. Fenêtres, affichage, accessibilité

Vérifiez la taille de fenêtre minimale, une grande fenêtre, l'échelle Retina, Réduire les
animations, Augmenter le contraste, VoiceOver, l'accès clavier complet et une langue autre que le
coréen.

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Les boutons de la barre latérale, du canevas, de l'inspecteur, des feuilles, des réglages et de l'aide ne sont pas coupés. |  |
|  | Redimensionner la fenêtre garde la largeur des panneaux et le point de focus du canevas utilisables. |  |
|  | Dans une petite fenêtre Développement, seule la liste des dossiers et photos défile ; le reste de la barre latérale reste fixe. |  |
|  | Relancer restaure la disposition d'écran prise en charge. |  |
|  | Le texte ne descend jamais sous la taille définie et les valeurs importantes ne sont pas tronquées. |  |
|  | L'état des curseurs, roues, courbes, boutons segmentés, bascules et sélections se lit. |  |
|  | Noms, valeurs, indices, incréments et changements de sélection VoiceOver sont justes. |  |
|  | L'ordre clavier suit le flux visuel et le focus n'est pas piégé. |  |
|  | Réduire les animations supprime les mouvements inutiles, et Augmenter le contraste reste lisible. |  |
|  | Les textes produit changent de langue tandis que les identifiants techniques restent tels quels. |  |
|  | Les surfaces Liquid Glass n'affichent aucune ombre visible. |  |

## 5. Plugins externes et scanners réels

L'implémentation SANE s'installe et se configure depuis la distribution séparée
`negaflow-scanner-sane`.
Les preuves sur le plugin et l'appareil vont dans ce dépôt et dans cette fiche.

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Un plugin vu pour la première fois doit être approuvé par l'utilisateur. |  |
|  | Supprimer ou remplacer un plugin annule l'approbation précédente. |  |
|  | La détection ne montre que les appareils réels signalés par le plugin. |  |
|  | Résolution, profondeur de bits, mode, zone, aperçu, exposition et IR n'affichent que les capacités signalées. |  |
|  | Les capacités non prises en charge sont masquées ou donnent une raison exacte de désactivation. |  |
|  | Aperçu, scan complet, annulation, expiration, déconnexion et arrêt du plugin se terminent proprement. |  |
|  | Taille, profondeur de bits, zone et réglages appliqués du résultat correspondent aux valeurs signalées. |  |
|  | `detect --json` et `capabilities <id> --json` en CLI concordent avec l'écran de l'application. |  |
|  | Fichiers, dépendances, configuration et journaux du plugin restent hors de l'application et de ce dépôt. |  |

## 6. GrainMend et qualité d'image

Couvrez négatif couleur, noir et blanc chromogène pris en charge, noir et blanc argentique
ordinaire, diapositives, images propres, poussières, rayures, grain, visages, ciel et motifs fins.

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | GrainMend n'est pas présenté comme équivalent au nettoyage IR matériel d'un tiers. |  |
|  | Les défauts visés diminuent sans abîmer la texture et les contours. |  |
|  | Les fausses détections sur images propres restent acceptables. |  |
|  | RVB et IR coïncident, et un film décalé ou non pris en charge échoue clairement. |  |
|  | L'IR respecte les limites par type de film et préserve le matériel source. |  |
|  | Les recadrages à 100 % avant/après et les masques sont conservés avec les réglages et la version de l'application. |  |

## 7. Performance et mémoire

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Régler et se déplacer en boucle sur une photo 24 MP reste utilisable. |  |
|  | Régler et se déplacer en boucle sur une photo 48 MP reste utilisable. |  |
|  | Le développement et l'export aboutissent aux tailles de scan 3600 DPI et 7200 DPI. |  |
|  | Traiter un film de 48 vues ne mélange jamais l'état entre les images. |  |
|  | L’aperçu Tirage de 39 photos et les deux exports évitent un aperçu pleine résolution stabilisé par photo, restent réactifs et bornent la mémoire. |  |
|  | Sous pression mémoire, seuls les caches non sélectionnés sont libérés et l'image en cours reste. |  |
|  | Recherche, filtre et tri sur un grand catalogue restent utilisables sur le Mac testé. |  |
|  | Le défilement répété d’un catalogue de 2 000 photos dans l’app Release garde le processus vivant ; CPU et échantillon du thread principal sont consignés. |  |
|  | La chaleur, la mémoire et l'usage disque des traitements longs sont notés. |  |

## 8. Mise à jour et publication

| Résultat | À vérifier | Preuve ou problème |
|---|---|---|
|  | Les catalogues et fichiers annexes existants survivent à la mise à jour. |  |
|  | Les anciennes versions et schémas non pris en charge échouent proprement et expliquent comment récupérer. |  |
|  | Le lot de publication contient l'application, le dSYM, les sommes de contrôle, la licence et les listes nécessaires. |  |
|  | Matériel de test, originaux, identifiants et implémentation du plugin ne sont pas dans le lot. |  |
|  | Les problèmes connus et les preuves d'appareil et de profil concordent avec les notes de version. |  |

Décision de publication : `APPROVE`, `REJECT`, `BLOCKED`

- Décision :
- Identifiants des problèmes bloquants :
- Identifiants des problèmes non bloquants acceptés, et pourquoi :
- Emplacement du lot de preuves :
- Signature :

Si l'un des points suivants se reproduit, c'est un `REJECT` automatique jusqu'à correction et
nouvelle vérification.

- Modification de la source
- Réinitialisation silencieuse du catalogue
- Repli sur la source en cas d'échec d'export
- Affichage de capacités de scanner factices
- Publication d'une partie seulement de la sortie
- Décalage de signature ou de notarisation
- Perte de données
