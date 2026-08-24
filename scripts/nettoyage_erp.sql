-- ============================================================
-- Nettoyage de erp.xlsx (DuckDB)
-- Clé primaire : product_id
-- Étape 1 : suppression des valeurs manquantes
-- Étape 2 : dédoublonnage
-- ============================================================

-- L'extension "excel" permet à DuckDB de lire directement un .xlsx
INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE erp_clean AS
SELECT DISTINCT ON (product_id) *
FROM read_xlsx('erp.xlsx')
-- --- Suppression des valeurs manquantes ---
-- On garde uniquement les lignes où les colonnes essentielles sont renseignées
WHERE product_id IS NOT NULL
  AND price IS NOT NULL
  AND stock_quantity IS NOT NULL
  AND stock_status IS NOT NULL
-- --- Dédoublonnage ---
-- DISTINCT ON (product_id) ne garde qu'une seule ligne par product_id
ORDER BY product_id;

-- Export du résultat nettoyé (sera utilisé par l'étape de jointure)
COPY erp_clean TO 'erp_clean.csv' (HEADER, DELIMITER ',');

-- Vérification rapide (utile pour le test qui suivra cette tâche)
SELECT COUNT(*) AS nb_lignes, COUNT(DISTINCT product_id) AS nb_product_id_uniques
FROM erp_clean;
