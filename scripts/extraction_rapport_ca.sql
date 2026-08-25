-- ============================================================
-- Extraction finale : rapport CA au format Excel (XLSX)
-- Combine le CA par produit et le CA total dans un seul fichier
-- (le CA total apparaît comme une ligne "TOTAL" en bas du rapport)
-- ============================================================

CREATE OR REPLACE TABLE ca_par_produit AS SELECT * FROM read_csv_auto('ca_par_produit.csv');
CREATE OR REPLACE TABLE ca_total AS SELECT * FROM read_csv_auto('ca_total.csv');

INSTALL excel;
LOAD excel;

COPY (
    SELECT
        CAST(product_id AS VARCHAR) AS product_id,
        sku,
        nom_produit,
        price,
        quantite_vendue,
        chiffre_affaires
    FROM ca_par_produit
    UNION ALL
    SELECT
        '' AS product_id,
        '' AS sku,
        'TOTAL' AS nom_produit,
        NULL AS price,
        NULL AS quantite_vendue,
        chiffre_affaires_total AS chiffre_affaires
    FROM ca_total
) TO 'rapport_ca_bottleneck.xlsx' WITH (FORMAT xlsx, HEADER true);
