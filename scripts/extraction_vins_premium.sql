-- ============================================================
-- Extraction finale : vins premium
-- Relit vins_premium.csv (produit par la tâche zscore) et le
-- réexporte en tant que livrable final, avec outputFiles déclaré
-- sur la tâche Kestra correspondante.
-- ============================================================

CREATE OR REPLACE TABLE vins_premium AS SELECT * FROM read_csv_auto('vins_premium.csv');

COPY vins_premium TO 'vins_premium_final.csv' (HEADER, DELIMITER ',');
