# Journal de bord — Projet BottleNeck

## Étape 1 — Diagramme de flux
- Diagramme réalisé sur Draw.io (`logigramme_bottleneck.drawio`)
- Structure : 3 branches parallèles de nettoyage (erp, liaison, web) → convergence sur la jointure → séquentiel (calcul CA puis z-score, fidèle à l'ordre décrit par Stéphane) → branchement final en 3 extractions
- Chaque test a un chemin OK et un chemin KO (vers un nœud d'alerte/arrêt commun) — plus rigoureux qu'un simple chemin de succès

## Étape 2 — Installation Kestra
- Installation via Docker Compose (choix : plus robuste/persistant qu'un simple `docker run`, adapté à un projet développé sur plusieurs sessions)
- Conteneurs : `bottleneck-kestra-kestra-1` (port 8080) + `bottleneck-kestra-postgres-1`
- Interface accessible sur http://localhost:8080, compte créé, capture d'écran faite

## Exploration des fichiers sources

### erp.xlsx
- 825 lignes, 5 colonnes : `product_id` (int), `onsale_web` (0/1), `price` (float), `stock_quantity` (int), `stock_status` (instock/outofstock)
- Clé primaire probable : `product_id` (825 valeurs uniques, aucun doublon)
- Aucune valeur manquante, aucun doublon déjà présent
- ✅ Correspond au chiffre de contrôle de Laurent : 825 lignes après dédoublonnage
- ⚠️ Anomalie repérée : prix minimum = -8.0 (valeur négative suspecte). N'est ni un NA ni un doublon donc non traité par l'étape 1 de nettoyage — à garder en tête pour la suite (impact possible sur calcul CA / z-score), à mentionner si questionné en soutenance.

### web.xlsx
- 28 colonnes (export brut type WooCommerce/CMS), 1513 lignes au départ
- Colonnes utiles : `sku` (identifiant produit), `post_title` (nom du vin), `total_sales`, `average_rating`, `post_type`
- 83 lignes entièrement vides (parasites) → nettoyage = suppression des lignes où `sku` est manquant (85 valeurs manquantes) → 1513 − 85 = **1428 lignes** ✅ (correspond au contrôle de Laurent)
- Chaque produit apparaît en double dans le fichier brut : une ligne `post_type = "product"` + une ligne `post_type = "attachment"` (image), même `sku`
- Dédoublonnage sur `sku` : 1428 → **714 skus uniques** ✅ (correspond au contrôle de Laurent)
- ⚠️ Anomalie repérée : sur les 714 skus, **3 ont des valeurs `total_sales` différentes** entre leur ligne "product" et leur ligne "attachment" — incohérence mineure de données, à mentionner si questionné.

### liaison.xlsx
- 2 colonnes seulement : `product_id` (clé vers erp) et `id_web` (clé vers web.sku)
- 825 lignes, `product_id` déjà unique (825/825, 0 doublon), aucune ligne dupliquée
- ✅ Correspond au contrôle : "Après dédoublonnage du fichier liaison : 825 lignes" (le fichier était déjà propre)
- 91 valeurs manquantes sur `id_web` (734 renseignées) — **non supprimées** au nettoyage puisque `product_id` (la clé) est intact. Ces lignes seront naturellement exclues lors de la jointure avec web.xlsx (un `id_web` vide ne matche aucun `sku`)
- Cohérent avec le résultat final : fichier fusionné = 714 lignes = exactement le nombre de produits web uniques → la jointure est pilotée par web.xlsx

## Scripts SQL de nettoyage (testés sur les vraies données)
- `nettoyage_erp.sql` : filtre sur 4 colonnes essentielles + DISTINCT ON (product_id) → 825 lignes ✅
- `nettoyage_web.sql` : filtre sur sku uniquement + DISTINCT ON (sku) → 1428 puis 714 lignes ✅
- `nettoyage_liaison.sql` : filtre sur product_id uniquement (id_web toléré vide) + DISTINCT ON (product_id) → 825 lignes ✅
- Tous testés dans le sandbox via CSV temporaires (l'extension DuckDB "excel" nécessite un accès internet non disponible dans le sandbox, mais fonctionnera dans l'environnement réel de Dorra)

## Script SQL de jointure (`jointure.sql`)
- INNER JOIN : web_clean → liaison_clean (sur sku = id_web) → erp_clean (sur product_id)
- Jointure pilotée par web_clean (714 lignes) : chaque produit web trouve son id_web dans liaison, puis son product_id dans erp
- Testé sur les vraies données : **714 lignes en sortie, 0 doublon créé** ✅ (correspond au chiffre de contrôle de Laurent)
- Colonnes conservées : sku, post_title, total_sales, average_rating (web) + product_id, price, stock_quantity, stock_status (erp)

## ⚠️ Bug découvert et corrigé — dédoublonnage de web.xlsx
- En calculant le CA total pour vérifier le chiffre de contrôle (70 568.60 €), écart initial constaté : 65 652.60 € (-4 916 €)
- Cause : sur 714 skus, **3 ont des `total_sales` différents entre leur ligne "product" et leur ligne "attachment"** (ex : sku 7818 → 96 sur la ligne "product" vs seulement 6 sur "attachment")
- Le dédoublonnage initial (`DISTINCT ON (sku) ORDER BY sku`) ne précisait pas laquelle des deux lignes garder → résultat non déterministe / incorrect
- **Correction** : `ORDER BY sku, CASE WHEN post_type = 'product' THEN 0 ELSE 1 END` → priorise explicitement la ligne "product" (données commerciales fiables)
- Après correction : **CA total = 70 568.60 € exactement** ✅
- Script `nettoyage_web.sql` mis à jour en conséquence. Bon exemple à citer en soutenance : illustre l'intérêt de valider chaque étape avec les chiffres de contrôle plutôt que de supposer que le résultat est juste.

## Script Python de détection z-score (`zscore_vins.py`)
- Calcul sur `fusion.csv` (714 lignes), colonne `price`
- z-score = (price - moyenne) / écart-type (échantillon, ddof=1)
- Seuil : z-score > 2 → premium, sinon ordinaire
- Testé sur les vraies données (exécution complète du script) : **30 vins premium, 684 vins ordinaires** ✅ (30 = chiffre de contrôle exact de Laurent)
- Produit 2 fichiers : `vins_premium.csv`, `vins_ordinaires.csv`

## ✅ Checklist de fin d'étape (avant de passer à l'assemblage Kestra)
- [ ] `docker-compose.yml` à la racine de `bottleneck-kestra/`
- [ ] `logigramme_bottleneck.drawio` à la racine
- [ ] `journal_de_bord.md` à la racine (ce fichier)
- [ ] Dossier `scripts/` contenant les 6 fichiers :
  - [ ] `nettoyage_erp.sql`
  - [ ] `nettoyage_web.sql` (version corrigée avec `CASE WHEN post_type`)
  - [ ] `nettoyage_liaison.sql`
  - [ ] `jointure.sql`
  - [ ] `calcul_ca.sql`
  - [ ] `zscore_vins.py`
- [ ] Kestra accessible sur http://localhost:8080 (conteneurs "Up")
- [ ] Capture d'écran de Kestra faite (pour la soutenance)

## Chiffres de contrôle — tous validés ✅
| Étape | Attendu | Obtenu |
|---|---|---|
| erp nettoyé | 825 | 825 |
| liaison nettoyé | 825 | 825 |
| web nettoyé (NA) | 1428 | 1428 |
| web dédoublonné | 714 | 714 |
| fichier fusionné | 714 | 714 |
| CA total | 70 568.60 € | 70 568.60 € |
| vins premium | 30 | 30 |

## Étape 3 — Assemblage Kestra (en cours)
- Architecture retenue : un seul `WorkingDirectory` avec `namespaceFiles: enabled: true` enveloppant toutes les tâches → les 3 xlsx + le dossier `scripts/` sont automatiquement disponibles pour chaque tâche, sous leurs noms exacts (aucune modification des scripts déjà écrits nécessaire)
- Scripts SQL exécutés via `io.kestra.plugin.jdbc.duckdb.Queries`, avec `sql: "{{ read('scripts/xxx.sql') }}"` pour référencer les fichiers déjà écrits/testés sans dupliquer le code dans le YAML
- `fetchType: FETCH` ajouté sur chaque tâche pour rendre les résultats visibles dans l'onglet Outputs de Kestra (utile pour la démonstration en soutenance)
- Tests construits avec la fonction `error()` de DuckDB : fait échouer la tâche (statut FAILED) si un contrôle échoue, ce qui permettra le routage vers un chemin d'erreur (KO), fidèle au diagramme
- **Brique 1 validée en exécution réelle** : `nettoyage_erp` → 825 lignes ✅ ; `test_erp` → "Test réussi : erp_clean ne contient ni doublon ni valeur manquante" ✅
- Point mineur observé : un WARN Kestra sur une extension DuckDB interne ("ion") au chargement — sans rapport avec nos scripts, sans impact sur l'exécution, à ignorer

## ⚠️ Bug découvert en exécution réelle Kestra — lecture xlsx
- `nettoyage_erp` + `test_erp` : SUCCESS en conditions réelles (825 lignes, test passé) — première confirmation que `read_xlsx()` fonctionne vraiment (pas testable dans mon sandbox, faute d'accès internet à l'extension DuckDB "excel")
- `nettoyage_web` a échoué : `Failed to parse cell 'A198': Could not convert string 'bon-cadeau-25-euros' to DOUBLE`
- Cause : DuckDB `read_xlsx()` devine un type unique par colonne. La colonne `sku` est presque toujours numérique, sauf pour un produit **"Bon cadeau de 25€"** dont le sku est le texte `bon-cadeau-25-euros`. DuckDB plante au lieu de traiter la colonne comme texte.
- ⚠️ Vérifié avant de corriger : ce produit fait bien partie des 714 lignes déjà validées (ce n'est pas une erreur de données à exclure, c'est un vrai produit vendu) — il ne fallait donc pas le supprimer silencieusement (option `ignore_errors=true` aurait été plus simple mais aurait cassé le CA total)
- **Correction** : `read_xlsx('web.xlsx', all_varchar = true)` (tout lire en texte) + `TRY_CAST(total_sales AS DOUBLE)` / `TRY_CAST(average_rating AS DOUBLE)` pour reconvertir explicitement les seules colonnes réellement numériques
- Même correctif appliqué préventivement à `nettoyage_liaison.sql` (colonne `id_web` : mêmes valeurs textuelles repérées : `bon-cadeau-25-euros`, `13127-1`, `14680-1`) → `TRY_CAST(product_id AS BIGINT)`, `id_web` gardé en texte
- Revalidé après correction : 714 lignes, CA total = 70 568.60 €, 30 vins premium — **identique aux résultats déjà validés**, rien n'a changé côté résultat, seule la robustesse de lecture est améliorée
- `jointure.sql` n'a nécessité aucune modification (il sélectionnait déjà uniquement les colonnes utiles, pas de `SELECT *`)
- Bon exemple à citer en soutenance sur le point de vigilance "réception de nouvelles sources de données" : la lecture de fichiers Excel bruts doit anticiper des colonnes au typage mixte

## Incident — perte d'accès Kestra après une pause
- Après une interruption de plusieurs jours, le conteneur `kestra` avait disparu (`docker compose ps` ne montrait plus que `postgres`, actif en continu) — probablement un arrêt du conteneur applicatif sans que le conteneur de base de données ne soit affecté
- `docker compose up -d` a recréé le conteneur Kestra normalement
- Ensuite : connexion impossible ("Invalid username or password"), alors que les identifiants étaient corrects. Cause : les identifiants du compte utilisateur, définis via la page de configuration initiale, sont stockés dans PostgreSQL — mais la base a persisté sans interruption, donc ce n'était pas une perte de compte, plutôt un identifiant mal mémorisé après la coupure
- **Solution appliquée (méthode officielle Kestra, sans perte de données)** : définir des identifiants explicites directement dans `docker-compose.yml`, dans la section `KESTRA_CONFIGURATION > kestra > server > basic-auth` (présente mais commentée par défaut dans le template officiel). Le fichier de configuration prend toujours le pas sur les valeurs enregistrées via la page de setup.
- Toutes les données (namespace `bottleneck`, fichiers, flow) sont restées intactes tout du long : elles vivent dans les volumes Docker persistants (`postgres-data`, `kestra-data`), indépendants du cycle de vie du conteneur applicatif

## ✅ Brique "nettoyage" complète et validée en exécution réelle
Après correction des bugs de lecture xlsx (all_varchar + TRY_CAST), les 6 tâches passent toutes au vert dans Kestra : `nettoyage_erp`, `test_erp`, `nettoyage_web`, `test_web`, `nettoyage_liaison`, `test_liaison`. Exécution complète en ~3 secondes.

## Nettoyage final du projet avant dépôt GitHub
- **Identifiants extraits** de `docker-compose.yml` vers un fichier `.env` (non versionné, listé dans `.gitignore`) : `POSTGRES_PASSWORD`, `KESTRA_USERNAME`, `KESTRA_PASSWORD`. Bonne pratique de sécurité — un dépôt public ne doit jamais contenir de mot de passe en clair.
- **`pull_policy: always` retiré** : cette option forçait Docker à retélécharger l'image Kestra (~3 Go) à chaque démarrage, ce qui expliquait les temps d'attente longs pendant le développement, et a été la cause probable du décalage de version ayant provoqué le bug du dashboard (colonne "deleted" manquante en base). Sans cette ligne, Docker réutilise l'image déjà en cache localement.
- Projet déposé sur GitHub : `https://github.com/dorrazch-hue/bottleneck-data-pipeline`

## ✅ Jointure + calcul CA validés en exécution réelle
10 tâches au total maintenant vertes dans Kestra : les 6 précédentes + `jointure`, `test_jointure`, `calcul_ca`, `test_ca`.
- Le test de jointure vérifie : présence de résultats, absence de doublons (fan-out), cohérence de volumétrie
- Le test de CA vérifie volontairement la **cohérence structurelle** (positif, non nul, somme détail = total) plutôt qu'une valeur fixe (70 568.60 €) — le pipeline doit rester valide avec les données du mois prochain, qui auront un CA différent

