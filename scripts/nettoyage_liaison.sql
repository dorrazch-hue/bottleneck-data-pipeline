-- ============================================================
-- Nettoyage de liaison.xlsx (DuckDB)
-- Clé primaire : product_id
-- Étape 1 : suppression des valeurs manquantes
-- Étape 2 : dédoublonnage
-- ============================================================
-- Remarque : la clé de ce fichier est product_id (lien vers erp.xlsx).
-- La colonne id_web (lien vers web.sku) contient des valeurs manquantes,
-- mais on ne les supprime PAS ici : elles n'invalident pas la clé
-- primaire product_id. Ces lignes seront naturellement exclues lors de
-- la jointure avec web_clean (un id_web vide ne matche aucun sku).
--
-- Remarque 2 : comme pour web.xlsx, id_web contient des valeurs non
-- numériques (ex : 'bon-cadeau-25-euros', '13127-1'). On force donc
-- all_varchar=true à la lecture pour éviter que DuckDB ne plante en
-- essayant de deviner un type unique pour cette colonne, puis on
-- reconvertit uniquement product_id (réellement numérique) avec TRY_CAST.

INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE liaison_clean AS
SELECT DISTINCT ON (product_id)
    TRY_CAST(product_id AS BIGINT) AS product_id,
    id_web
FROM read_xlsx('liaison.xlsx', all_varchar = true)
-- --- Suppression des valeurs manquantes ---
-- On garde uniquement les lignes où la clé product_id est renseignée
WHERE product_id IS NOT NULL
-- --- Dédoublonnage ---
-- Une seule ligne conservée par product_id
ORDER BY product_id;

-- Export du résultat nettoyé (sera utilisé par l'étape de jointure)
COPY liaison_clean TO 'liaison_clean.csv' (HEADER, DELIMITER ',');

-- Vérification rapide (utile pour le test qui suivra cette tâche)
SELECT COUNT(*) AS nb_lignes, COUNT(DISTINCT product_id) AS nb_product_id_uniques
FROM liaison_clean;
