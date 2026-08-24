-- ============================================================
-- Nettoyage de web.xlsx (DuckDB)
-- Clé primaire : sku
-- Étape 1 : suppression des valeurs manquantes
-- Étape 2 : dédoublonnage
-- ============================================================
-- Remarque : web.xlsx est un export brut (type WooCommerce) où chaque
-- produit apparaît 2 fois (une ligne "product" + une ligne "attachment"
-- pour l'image associée, même sku). Le dédoublonnage sur sku règle ce cas.
--
-- Remarque 2 : la colonne sku n'est PAS toujours numérique (ex : un
-- produit "bon cadeau" a pour sku 'bon-cadeau-25-euros'). Sans précaution,
-- DuckDB essaie de deviner un type unique par colonne et plante en trouvant
-- ce genre de valeur texte. On force donc all_varchar=true à la lecture,
-- puis on reconvertit nous-mêmes les colonnes réellement numériques
-- (total_sales, average_rating) avec TRY_CAST, qui renvoie NULL au lieu de
-- planter en cas d'échec de conversion.

INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE web_clean AS
SELECT DISTINCT ON (sku)
    sku,
    post_title,
    post_type,
    TRY_CAST(total_sales AS DOUBLE) AS total_sales,
    TRY_CAST(average_rating AS DOUBLE) AS average_rating
FROM read_xlsx('web.xlsx', all_varchar = true)
-- --- Suppression des valeurs manquantes ---
-- On retire les lignes parasites où sku (la clé) est vide
WHERE sku IS NOT NULL
-- --- Dédoublonnage ---
-- Une seule ligne conservée par sku. IMPORTANT : on priorise explicitement
-- la ligne post_type='product' (données commerciales fiables) plutôt que
-- 'attachment' (métadonnée image), car ces 2 lignes peuvent porter des
-- valeurs total_sales différentes pour un même sku (vérifié sur les
-- données réelles : 3 cas sur 714, impact de -4916€ sur le CA total si
-- on ne fait pas cette distinction).
ORDER BY sku, CASE WHEN post_type = 'product' THEN 0 ELSE 1 END;

-- Export du résultat nettoyé (sera utilisé par l'étape de jointure)
COPY web_clean TO 'web_clean.csv' (HEADER, DELIMITER ',');

-- Vérification rapide (utile pour le test qui suivra cette tâche)
SELECT COUNT(*) AS nb_lignes, COUNT(DISTINCT sku) AS nb_sku_uniques
FROM web_clean;
