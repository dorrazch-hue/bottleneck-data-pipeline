# Journal de bord — Mission BottleNeck

## Jour 1 — Prise en main et diagramme

Premier réflexe : bien lire l'énoncé et surtout le mail de Laurent avant de toucher à quoi que ce soit. J'ai listé la démarche de Stéphane (nettoyage → jointure → CA → z-score) et j'ai gardé les fichiers `erp.xlsx`, `web.xlsx`, `liaison.xlsx` de côté pour l'instant, comme demandé — l'étape 1 est censée être purement conceptuelle.

Avant de me lancer dans le diagramme, j'ai relu les deux ressources conseillées (les 5 fonctionnalités de Draw.io, et la définition d'un logigramme sur Lucidchart). Utile pour se rappeler les bons symboles : ovale pour début/fin, rectangle pour une tâche, losange pour un test, parallélogramme pour une donnée en entrée/sortie.

Premier jet du logigramme : 3 branches parallèles (une par fichier source) qui convergent vers la jointure, puis calcul du CA et détection z-score en parallèle après la jointure. En le relisant, je me suis rendu compte que ça ne collait pas exactement au texte de Laurent : sa démarche décrit 4 étapes séquentielles (nettoyage, jointure, CA, z-score — dans cet ordre, pas en parallèle). J'ai corrigé pour rester fidèle à l'énoncé, ça sera plus facile à défendre en soutenance si on me demande pourquoi j'ai ordonnancé les tâches comme ça.

Autre chose que j'avais oubliée au premier jet : les tests. L'énoncé insiste bien dessus ("n'oubliez pas de schématiser les tests"). Ajouté un losange après chaque étape, avec un chemin d'échec (KO, en pointillés rouges) qui part vers un nœud d'alerte commun, plutôt qu'un losange par test — ça reste lisible.

## Installation de Kestra

Suivi le tuto officiel avec Docker Compose plutôt qu'un simple `docker run`, pour avoir quelque chose de plus durable vu que je vais travailler dessus sur plusieurs sessions. Téléchargement du `docker-compose.yml` officiel, `docker compose up -d`, et le premier démarrage a pris un certain temps (l'image Kestra fait dans les 3 Go). Une fois les conteneurs "Up", tout s'est bien passé.

## Exploration des 3 fichiers sources

Je me suis dit qu'il valait mieux regarder les fichiers avant d'écrire le moindre script SQL, pour ne pas avoir à deviner les noms de colonnes.

**erp.xlsx** : 825 lignes, 5 colonnes. Déjà propre — aucun doublon, aucune valeur manquante. Un point surprenant : un prix minimum à -8€, ce qui n'a pas de sens. Pas une valeur manquante ni un doublon donc pas concerné par le nettoyage de l'étape 1, mais je le note au cas où ça ressort plus tard.

**web.xlsx** : plus délicat. 28 colonnes (export brut type WooCommerce), 1513 lignes au départ. 83 lignes complètement vides. Et surtout : chaque produit apparaît deux fois (une ligne `post_type = product`, une ligne `post_type = attachment` pour l'image, même sku). Après filtrage des lignes vides sur `sku` : 1428 lignes — ça correspond au chiffre de contrôle de Laurent. Après dédoublonnage sur `sku` : 714 — ça correspond aussi.

**liaison.xlsx** : le plus simple des trois. 825 lignes, `product_id` (vers erp) et `id_web` (vers web.sku). Déjà propre sur sa clé `product_id`. 91 valeurs manquantes sur `id_web`, mais je ne les supprime pas — elles ne posent pas de problème pour la clé primaire, et elles seront de toute façon exclues naturellement à la jointure.

## Écriture des scripts SQL / Python

Testé chaque script avant de le considérer fini — pas question de livrer un script qui "devrait marcher" sans l'avoir fait tourner sur les vraies données. Une bonne pratique qui m'a évité pas mal de mauvaises surprises, sauf une :

**Le CA qui ne correspondait pas au chiffre attendu.** En calculant le CA total pour vérifier (attendu : 70 568,60 €), j'obtenais 65 652,60 € — un écart de 4 916 €. En creusant : sur les 714 produits, 3 ont des `total_sales` différents entre leur ligne "product" et leur ligne "attachment" (le duplicata mentionné plus haut). Mon dédoublonnage ne précisait pas laquelle des deux garder. Corrigé en priorisant explicitement la ligne `post_type = 'product'`. Résultat : 70 568,60 € exactement. Un bon rappel de l'intérêt de vérifier un résultat contre un chiffre de contrôle plutôt que de supposer qu'il est correct.

Pour le z-score : `(prix - moyenne) / écart-type`, seuil > 2 pour "premium". 30 vins premium trouvés, cohérent avec le chiffre donné.

## Montage du workflow Kestra

Architecture retenue au départ : un seul `WorkingDirectory` qui enveloppe toutes les tâches, avec `namespaceFiles: enabled: true`. Les scripts SQL/Python restent dans des fichiers séparés et sont appelés depuis le YAML via `{{ read('scripts/...') }}`.

Première brique (nettoyage erp + test) : fonctionnelle dès le premier essai.

Ensuite, `nettoyage_web` a échoué avec une erreur DuckDB assez peu explicite au premier abord : impossible de convertir `'bon-cadeau-25-euros'` en nombre. En fait le catalogue contient un produit "Bon cadeau" dont le sku est du texte, pas un identifiant numérique comme les autres. Corrigé avec `all_varchar = true` à la lecture, puis reconversion ciblée des colonnes réellement numériques. Même correctif appliqué à `liaison.xlsx` par précaution.

## Le script Python et la question du z-score

Ce point m'a pris beaucoup de temps. Le symptôme : le script Python n'arrivait jamais à trouver `fusion.csv`, peu importe l'emplacement testé.

Après plusieurs pistes infructueuses (conteneur Docker séparé, mode "Process", recherche dans le dossier du script, recherche large sur tout le système), une tâche de diagnostic simple (`find / -name fusion.csv`) a fini par le localiser à `/app/fusion.csv`. Explication : toutes les tâches SQL DuckDB tournent en fait dans le même processus que le serveur Kestra lui-même, et partagent donc son dossier `/app`. Les tâches Python, elles, tournent dans un sous-processus à part, avec un dossier temporaire différent. Une fois cette différence comprise, le correctif est simple : faire pointer le script vers `/app/fusion.csv` directement.

Ce type de problème demande surtout de la méthode et de ne pas abandonner la piste en cours de route.

## Nettoyage avant dépôt GitHub

Avant de rendre le projet public : sorti les mots de passe du `docker-compose.yml` vers un `.env` (non versionné), et retiré le `pull_policy: always` qui forçait un retéléchargement de 3 Go à chaque démarrage.

## La parallélisation, et la difficulté avec le Switch

Mon mentor Sylvain a testé le pipeline sur ses propres fichiers et m'a fait un retour précis : mes trois nettoyages tournaient en réalité toujours les uns après les autres, alors que je les présentais comme parallélisés. Et le `Switch` que j'avais ajouté se contentait de confirmer un succès générique, sans vraiment décider quoi extraire selon la présence ou non de vins premium ce mois-là.

La parallélisation s'est réglée assez rapidement, avec une chose utile apprise au passage : dans Kestra, `Parallel`, comme `Switch`, ne peut pas être placé directement à l'intérieur d'un `WorkingDirectory` — j'ai dû sortir chaque branche (erp / web / liaison) dans son propre `WorkingDirectory`. Comme les tâches DuckDB partagent toutes `/app` de toute façon, la suite du pipeline retrouve les fichiers nettoyés sans problème.

Le Switch a demandé plus de temps. Peu importe comment j'écrivais la condition pour aller lire le résultat d'un comptage de vins premium, Kestra renvoyait la même erreur interne, sans détail exploitable. J'ai fini par abandonner l'idée d'aller chercher une valeur calculée, et je suis revenue à un mécanisme dont j'étais sûre qu'il fonctionnait déjà dans mon projet : vérifier si une tâche a réussi ou échoué, plutôt que d'aller lire ce qu'elle a renvoyé. Ça a fonctionné dès le premier essai.

Au passage, j'en ai profité pour ajouter la vraie version XLSX du rapport CA (le diagramme le promettait depuis le début, le script ne le produisait pas encore), et pour déposer les vrais fichiers de résultat sur le dépôt plutôt que de simplement affirmer qu'ils existent.

## Un défaut de conception, puis un second bug découvert en le vérifiant

Un retour ultérieur a pointé un vrai défaut de conception : ma tâche de comptage des vins premium utilisait `error()` pour échouer volontairement quand il n'y en avait aucun. Mais dans ce cas précis, le pipeline ne parvenait jamais jusqu'au Switch, donc cette branche "aucun vin premium" ne pouvait en réalité jamais s'exécuter. Une tâche censée simplement compter ne devrait pas échouer sur un résultat de zéro, qui reste une valeur valide.

J'ai séparé le traitement en deux tâches : une qui compte et réussit toujours (même à zéro), et une autre, dédiée, qui effectue le vrai test et échoue si besoin — c'est son état que le Switch observe.

Plutôt que de supposer que le correctif fonctionnait, j'ai voulu le vérifier concrètement : modification temporaire du script z-score pour simuler un mois sans aucun vin premium, exécution complète du pipeline, puis retour au script d'origine. Ce test a immédiatement révélé un second bug, invisible jusque-là : quand le fichier des vins premium est vide, DuckDB ne parvient plus à déterminer le type de la colonne z-score et la traite comme du texte, ce qui fait échouer toute comparaison numérique plus loin dans un test. Corrigé avec un cast explicite du type de colonne.

Une leçon confirmée deux fois cette semaine : un correctif qui semble correct sur le papier peut encore contenir un problème tant que le chemin qu'il est censé emprunter n'a pas été réellement exécuté au moins une fois.

## Une dernière vérification avant de clore le dépôt

En relisant l'ensemble une dernière fois de façon critique, j'ai remarqué que le script Python de production avait perdu, à un moment donné, la recherche du fichier dans `/app` — probablement un mauvais remplacement entre deux versions au cours des nombreuses modifications. Remis en place et retesté.

Autre point notable : mon README avait été, à un moment donné, entièrement remplacé par celui d'un autre projet personnel en cours (un portfolio autour d'un chatbot RAG, sans rapport avec celui-ci). Les deux fichiers portaient le même nom dans mon dossier de téléchargements, et le mauvais a fini par être poussé sur GitHub à la place du bon. Une vérification ligne par ligne directement dans le terminal m'a permis de m'en apercevoir et de rétablir le bon contenu. Une bonne raison de toujours vérifier le contenu d'un fichier avant de le déplacer, pas seulement son nom.
