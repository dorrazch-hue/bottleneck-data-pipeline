-- ============================================================
-- Calcul du chiffre d'affaires (DuckDB)
-- Sur les données fusionnées (fusion.csv, 714 lignes)
-- CA par produit = price * total_sales
-- ============================================================

INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE fusion AS SELECT * FROM read_csv_auto('fusion.csv');

-- CA par produit
CREATE OR REPLACE TABLE ca_par_produit AS
SELECT
    product_id,
    sku,
    post_title AS nom_produit,
    price,
    total_sales AS quantite_vendue,
    ROUND(price * total_sales, 2) AS chiffre_affaires
FROM fusion
ORDER BY chiffre_affaires DESC;

-- Export du rapport CA par produit
COPY ca_par_produit TO 'ca_par_produit.csv' (HEADER, DELIMITER ',');

-- CA total
CREATE OR REPLACE TABLE ca_total AS
SELECT ROUND(SUM(chiffre_affaires), 2) AS chiffre_affaires_total
FROM ca_par_produit;

COPY ca_total TO 'ca_total.csv' (HEADER, DELIMITER ',');

-- Vérification rapide (utile pour le test de cohérence du CA qui suivra cette tâche)
SELECT * FROM ca_total;
