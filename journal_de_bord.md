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

Architecture retenue : un seul `WorkingDirectory` qui enveloppe toutes les tâches, avec `namespaceFiles: enabled: true` pour que les fichiers sources soient dispo partout sans prise de tête. Les scripts SQL/Python restent dans des fichiers séparés (uploadés comme Namespace Files) et sont appelés depuis le YAML via `{{ read('scripts/...') }}` — ça évite de tout recopier dans le YAML.

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
- Il restait à figer la version de l'image plutôt que `latest`. Ma première tentative (un numéro de version que j'avais vu affiché dans l'interface Kestra) ne correspondait en fait à aucun tag Docker existant — build échoué. Utilisé le tag officiel `latest-lts`, documenté par Kestra comme plus stable (mis à jour tous les 6 mois environ, contre en continu pour `latest`).

Repassé une exécution complète après tout ça : toujours vert, 14 tâches, résultats cohérents avec les chiffres de contrôle.
