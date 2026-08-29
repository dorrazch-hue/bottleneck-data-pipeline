# Journal de bord — Mission BottleNeck

## Jour 1 — Prise en main et diagramme

Premier réflexe : bien lire l'énoncé et surtout le mail de Laurent avant de toucher à quoi que ce soit. J'ai listé la démarche de Stéphane (nettoyage → jointure → CA → z-score) et j'ai gardé les fichiers `erp.xlsx`, `web.xlsx`, `liaison.xlsx` de côté pour l'instant, comme demandé — l'étape 1 est censée être purement conceptuelle.

Avant de me lancer dans le diagramme, j'ai relu les deux ressources conseillées (les 5 fonctionnalités de Draw.io, et la définition d'un logigramme sur Lucidchart). Utile pour se rappeler les bons symboles : ovale pour début/fin, rectangle pour une tâche, losange pour un test, parallélogramme pour une donnée en entrée/sortie.

Premier jet du logigramme : 3 branches parallèles (une par fichier source) qui convergent vers la jointure, puis calcul du CA et détection z-score **en parallèle** après la jointure. En le relisant, je me suis rendu compte que ça ne collait pas exactement au texte de Laurent : sa démarche décrit 4 étapes **séquentielles** (nettoyage, jointure, CA, z-score — dans cet ordre, pas en parallèle). J'ai corrigé pour rester fidèle à l'énoncé, ça sera plus facile à défendre en soutenance si on me demande pourquoi j'ai ordonnancé les tâches comme ça.

Autre chose que j'avais oubliée au premier jet : les tests. L'énoncé insiste bien dessus ("n'oubliez pas de schématiser les tests"). Ajouté un losange après chaque étape, avec un chemin d'échec (KO, en pointillés rouges) qui part vers un nœud d'alerte commun, plutôt qu'un losange par test — ça reste lisible.

## Installation de Kestra

Suivi le tuto officiel avec Docker Compose plutôt qu'un simple `docker run`, pour avoir quelque chose de plus durable vu que je vais travailler dessus sur plusieurs sessions. Téléchargement du `docker-compose.yml` officiel, `docker compose up -d`, et ça a mis un moment la première fois (l'image Kestra fait dans les 3 Go). Une fois les conteneurs "Up", tout s'est bien passé — capture d'écran de l'accueil Kestra faite pour la présentation.

## Exploration des 3 fichiers sources

Je me suis dit qu'il valait mieux regarder les fichiers avant d'écrire le moindre script SQL, sinon je vais deviner les noms de colonnes.

**erp.xlsx** : 825 lignes, 5 colonnes (product_id, onsale_web, price, stock_quantity, stock_status). Déjà propre — aucun doublon, aucune valeur manquante. Un truc bizarre : un prix minimum à -8€, ce qui n'a pas de sens. Pas un NA ni un doublon donc pas concerné par le nettoyage de l'étape 1, mais je le note au cas où ça ressort plus tard (sur le calcul du CA ou le z-score).

**web.xlsx** : plus embêtant. 28 colonnes (export brut type WooCommerce), 1513 lignes au départ. 83 lignes complètement vides. Et surtout : chaque produit apparaît deux fois (une ligne `post_type = product`, une ligne `post_type = attachment` pour l'image, même sku). Après filtrage des lignes vides sur `sku` : 1428 lignes — ça correspond au chiffre de contrôle de Laurent. Après dédoublonnage sur `sku` : 714 — ça correspond aussi.

**liaison.xlsx** : le plus simple des trois. 825 lignes, `product_id` (vers erp) et `id_web` (vers web.sku). Déjà propre sur sa clé `product_id`. 91 valeurs manquantes sur `id_web`, mais je ne les supprime pas — elles ne posent pas de problème pour la clé primaire, et elles seront de toute façon exclues naturellement à la jointure (un `id_web` vide ne matche aucun `sku`).

## Écriture des scripts SQL / Python

Testé chaque script avant de le considérer fini — pas question de livrer un script "qui devrait marcher" sans l'avoir fait tourner sur les vraies données. Bonne pratique qui m'a évité pas mal de mauvaises surprises... sauf une, justement :

**Le bug du CA qui ne tombait pas juste.** En calculant le CA total pour vérifier (attendu : 70 568,60 €), je suis tombée sur 65 652,60 € — un écart de 4 916 €. En creusant : sur les 714 produits, 3 ont des `total_sales` différents entre leur ligne "product" et leur ligne "attachment" (le duplicata dont je parlais plus haut). Mon dédoublonnage ne précisait pas laquelle des deux garder. Corrigé en priorisant explicitement la ligne `post_type = 'product'` (les vraies données commerciales). Résultat : 70 568,60 € pile. Content de m'être arrêtée sur ce chiffre de contrôle plutôt que de me dire "ça doit être bon".

Pour le z-score : `(prix - moyenne) / écart-type`, seuil > 2 pour "premium". 30 vins premium trouvés, ça correspond au chiffre donné.

## Montage du workflow Kestra

Architecture retenue (à ce stade du projet) : un seul `WorkingDirectory` qui enveloppe toutes les tâches, avec `namespaceFiles: enabled: true` pour que les fichiers sources soient dispo partout sans prise de tête. Les scripts SQL/Python restent dans des fichiers séparés (uploadés comme Namespace Files) et sont appelés depuis le YAML via `{{ read('scripts/...') }}` — ça évite de tout recopier dans le YAML.

*(Cette architecture à un seul `WorkingDirectory` a ensuite été revue en profondeur — voir la section "Deuxième retour de mentor" plus bas, qui introduit la parallélisation des nettoyages.)*

Première brique (nettoyage erp + test) : marche du premier coup, 825 lignes confirmées directement dans Kestra. Bon signe.

**Ensuite ça s'est compliqué.** `nettoyage_web` a planté avec une erreur DuckDB assez cryptique : impossible de convertir `'bon-cadeau-25-euros'` en nombre. En fait le catalogue contient un produit "Bon cadeau" dont le sku est du texte, pas un identifiant numérique comme les autres — et DuckDB essaie de deviner un type unique par colonne. Avant de corriger, j'ai vérifié que ce produit fait bien partie des 714 lignes déjà validées (donc pas question de le supprimer silencieusement, ça aurait faussé le CA). Corrigé avec `all_varchar = true` à la lecture + reconversion ciblée des colonnes réellement numériques. Même correctif appliqué à `liaison.xlsx` par précaution (même genre de valeurs textuelles dans `id_web`).

## La galère du script Python (z-score)

Celle-là m'a pris beaucoup, beaucoup de temps. Le symptôme : le script Python n'arrivait jamais à trouver `fusion.csv`, peu importe où je regardais.

J'ai tout essayé dans l'ordre : conteneur Docker séparé (le fichier n'était pas transmis), puis transmis mais vide ; passage en mode "Process" (pareil, introuvable) ; recherche dans le dossier du script lui-même ; recherche large avec `find /` sur tout le système — rien.

Ce qui a fini par débloquer les choses : une tâche de diagnostic toute bête (`find / -name fusion.csv`) qui a fini par le localiser à **`/app/fusion.csv`**. Explication : toutes les tâches SQL DuckDB tournent en fait dans le même processus que le serveur Kestra lui-même, et partagent donc son dossier `/app`. Les tâches Python, elles, tournent dans un sous-processus à part, avec un dossier temporaire complètement différent (`/tmp/kestra-wd/...`). Une fois qu'on comprend ça, le correctif est trivial : faire pointer le script vers `/app/fusion.csv` directement.

Ce genre de chose, je pense, ne s'invente pas — fallait juste être méthodique et ne pas lâcher l'affaire. Ça fera un bon sujet de discussion en soutenance sur les architectures d'orchestration.

## Nettoyage avant dépôt GitHub

Avant de pousser le projet en public : sorti les mots de passe du `docker-compose.yml` vers un `.env` (non versionné), et enlevé le `pull_policy: always` qui forçait un retéléchargement de 3 Go à chaque démarrage — sans doute la cause du bug bizarre de dashboard que j'ai eu à un moment (décalage entre la version de l'appli et le schéma de la base, après un redémarrage qui a dû choper une nouvelle image).

## Corrections après retour de mon mentor

Reçu une liste de points à corriger avant la soutenance. Les traités un par un :

- Le YAML du workflow n'était nulle part dans le dépôt — juste le docker-compose. Ajouté `bottleneck_pipeline.yaml` à la racine.
- Il manquait les 3 extractions finales comme vraies tâches visibles du pipeline. Ajouté une tâche dédiée `extraction_rapport_ca`, plus les `outputFiles` sur les tâches qui produisent déjà les CSV vins premium/ordinaires.
- Pas de planification automatique ni de gestion d'erreur dans le YAML. Ajouté un trigger cron (15 du mois, 9h), un `retry` sur chaque tâche, un handler `errors:` au niveau du flow, et un `Switch` de vérification finale (celui-là m'a demandé un aller-retour : Kestra n'autorise pas un `Switch` comme enfant direct d'un `WorkingDirectory`, il a fallu le sortir en tâche de premier niveau).
- Le diagramme annonçait un rapport CA en `.xlsx`, mais le script produisait du `.csv`. En creusant, DuckDB sait très bien écrire du xlsx directement (`COPY ... WITH (FORMAT xlsx)`), pas besoin de passer par autre chose.
- Pas de README ni de `.env.example`. Écrit les deux, avec les instructions d'installation, l'emplacement où déposer les 3 fichiers sources, comment importer le flow, et où récupérer les résultats.
- Il restait à figer la version de l'image plutôt que `latest`. Ma première tentative (un numéro de version que j'avais vu affiché dans l'interface Kestra) ne correspondait en fait à aucun tag Docker existant — build échoué. Utilisé le tag officiel `latest-lts`, documenté par Kestra comme plus stable (mis à jour tous les 6 mois environ, contre en continu pour `latest`). *(Remplacé plus tard par une version précise, `v1.3.33` — voir plus bas.)*

Repassé une exécution complète après tout ça : toujours vert, 14 tâches, résultats cohérents avec les chiffres de contrôle.

## Deuxième retour de mentor (Sylvain) — et la vraie galère du Switch

Nouveau retour, cette fois de Sylvain, après qu'il a lui-même exécuté le pipeline sur ses propres fichiers. Quatre points :

1. Les 3 nettoyages tournaient en fait toujours **séquentiellement** dans le YAML, alors que mon README affichait fièrement "en parallèle". Un mensonge involontaire qu'il a bien fait de relever.
2. Le `Switch` que j'avais ajouté ne faisait que confirmer un succès générique — pas ce qui était attendu, à savoir l'utiliser pour vraiment gérer les branches d'extraction vins premium / vins ordinaires.
3. Il fallait aussi que je récupère concrètement les 3 fichiers produits (le rapport et les deux CSV), pas juste qu'ils existent dans Kestra.
4. Le tag `latest-lts` restait évolutif — mieux vaudrait une version précise (remarque notée comme secondaire).

**La parallélisation** s'est réglée assez proprement, avec une leçon utile : `Parallel`, comme `Switch`, est un type de tâche "flowable" — impossible de le mettre directement à l'intérieur d'un `WorkingDirectory` (même règle qu'on avait découverte pour le Switch). Solution : chaque branche (erp / web / liaison) a son propre petit `WorkingDirectory`, avec le chargement des fichiers sources à chaque fois. Comme les tâches DuckDB partagent toutes `/app` (voir plus haut), la suite du pipeline retrouve les fichiers nettoyés sans problème, peu importe dans quelle "boîte" `WorkingDirectory` ils ont été produits. Testé, marché du premier coup.

**La version Kestra précise** m'a fait perdre un peu de temps bêtement : `kestra/kestra:1.3.33` n'existait pas comme tag Docker. En vérifiant sur le vrai Docker Hub (pas en devinant depuis GitHub), j'ai vu que tous les tags de version ont un `v` devant : `kestra/kestra:v1.3.33`. Corrigé, ça a marché directement.

**Le Switch pour vins premium / ordinaires**, en revanche... ça a été très long. Le principe : une tâche qui compte les vins premium détectés, puis un `Switch` qui route soit vers les deux extractions (premium + ordinaires), soit vers l'extraction des ordinaires seuls si aucun vin premium n'est détecté ce mois-là (cas limite qui a du sens : pas la peine d'extraire un fichier vide).

Le problème : peu importe comment j'écrivais la condition du Switch pour aller lire le résultat du comptage (`outputs.compteur.rows[0].nb_premium`, avec ou sans filtre de conversion en nombre, avec la notation par points ou par crochets), Kestra renvoyait toujours la même erreur générique — "Unable to save output" — sans aucun détail exploitable, même dans les logs bruts du conteneur. J'ai dû procéder par élimination :

- Testé avec une valeur strictement fixe (`value: "true"`) → ça marche, donc le Switch en lui-même n'est pas cassé
- Déplacé la tâche de comptage en dehors de son `WorkingDirectory` (au cas où ce serait un problème de portée) → même erreur
- Cherché sur les issues GitHub de Kestra : découvert que la notation par points sur les sorties personnalisées est un point sensible connu, avec un correctif documenté (crochets), qui n'a pourtant rien changé chez moi
- Essayé la vraie librairie Python officielle de Kestra (`from kestra import Kestra; Kestra.outputs(...)`) plutôt que la syntaxe bas niveau — non testé jusqu'au bout, on a changé d'approche avant

Ce qui a fini par marcher : abandonner complètement l'idée d'aller chercher une valeur personnalisée depuis le Switch, et revenir à un mécanisme dont j'étais déjà sûre qu'il fonctionnait dans mon environnement — celui utilisé pour tous mes tests depuis le début (la fonction `error()` de DuckDB). La tâche de comptage réussit s'il y a au moins un vin premium, et échoue volontairement sinon (avec `allowFailure: true` pour ne pas arrêter tout le pipeline). Le Switch se contente alors de vérifier l'état de cette tâche (`tasks.comptage_premium.state == 'SUCCESS'`) — exactement le même principe que mon tout premier Switch qui avait fonctionné, bien avant que je complique les choses en essayant d'aller chercher une valeur imbriquée.

Leçon retenue : quand un mécanisme marche déjà quelque part dans le projet, mieux vaut le réutiliser tel quel plutôt que d'aller chercher une solution plus "élégante" sur le papier mais qui s'avère fragile en pratique.

Exécution complète repassée après coup : les 4 tâches de premier niveau (parallélisation, suite du pipeline, comptage, Switch) toutes vertes, avec les 2 branches d'extraction (`extraction_vins_premium` et `extraction_vins_ordinaires`) qui se déclenchent correctement.

## Troisième retour — un vrai bug fonctionnel bien vu

Nouveau retour, avec un point fonctionnel précis cette fois : `comptage_premium.sql` utilisait `error()` pour échouer volontairement quand il n'y a aucun vin premium — mais dans ce cas précis, le pipeline ne parvenait jamais jusqu'au `Switch`, donc sa branche "aucun vin premium" ne pouvait en réalité jamais s'exécuter. Un vrai défaut de conception : une tâche censée juste *compter* ne devrait jamais échouer sur un résultat de zéro, qui est une valeur parfaitement valide.

Correction : séparation en deux tâches distinctes.
- `comptage_premium` redevient purement informatif — elle réussit **toujours**, et renvoie le vrai nombre (0 inclus).
- Une nouvelle tâche, `verification_premium_existe`, fait le vrai test (`error()` si zéro), et c'est **son état** (pas une valeur renvoyée) que le `Switch` regarde.

J'ai été tentée de revenir à la suggestion la plus directe (faire lire au Switch la valeur numérique renvoyée par `comptage_premium`), mais je me suis souvenue que c'est exactement ce qui avait échoué à répétition la première fois ("Unable to save output", quelle que soit la syntaxe essayée). Plutôt que de rouvrir ce chantier, j'ai gardé le mécanisme dont je suis sûre qu'il fonctionne (vérifier l'état d'une tâche) en le rendant simplement plus propre.

Quelques incohérences de documentation relevées au passage et corrigées : le journal mentionnait encore l'architecture à un seul `WorkingDirectory` et le tag `latest-lts` sans préciser qu'ils avaient été révisés depuis (précisions ajoutées plus haut) ; la présentation décrivait le Switch de façon un peu trop technique, sans expliquer la vraie logique métier derrière ; et les tâches d'extraction finales n'avaient pas de `retry`, contrairement à toutes les autres tâches du pipeline (ajouté).

**Test du cas limite, pour de vrai cette fois.** Plutôt que de me contenter de croire que le correctif fonctionne, j'ai testé le scénario "0 vin premium" en conditions réelles : modification temporaire du script z-score (seuil de classification rendu volontairement inatteignable), exécution complète, puis remise en place du vrai script. Bien m'en a pris : ce test a immédiatement révélé un **deuxième bug**, invisible jusque-là, dans `test_zscore.sql`. Quand `vins_premium.csv` ne contient aucune ligne de données (juste l'en-tête), DuckDB n'a rien à examiner pour deviner le type de la colonne `z_score`, et la traite par défaut comme du texte — ce qui fait planter toute comparaison numérique (`z_score <= 2`) avec une erreur de type. Corrigé avec un `CAST` explicite en `DOUBLE` à la lecture du CSV, qui force le bon type que la table soit vide ou non.

Deuxième round de test (car ma première tentative de simuler "0 vin premium" en changeant juste le seuil de classification créait elle-même une incohérence avec `test_zscore.sql`, qui vérifie contre le vrai seuil de 2) : cette fois en écrasant artificiellement l'écart-type plutôt que le seuil, pour que les z-scores réels restent authentiquement bas. Les deux scénarios (30 vins premium, et 0 vin premium) ont ensuite été validés de bout en bout, avec un vrai retour à la normale confirmé après remise en place du script définitif.

Cette étape confirme une leçon utile : un correctif qui "a l'air" correct sur le papier (ou même testé unitairement en local) peut encore cacher un bug si le chemin qu'il est censé emprunter n'est jamais réellement exécuté. Vaut mieux prendre le temps de simuler le cas limite plutôt que de le supposer fonctionnel.

