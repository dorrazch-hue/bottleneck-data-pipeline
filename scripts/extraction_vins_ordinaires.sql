-- ============================================================
-- Extraction finale : vins ordinaires
-- Relit vins_ordinaires.csv (produit par la tâche zscore) et le
-- réexporte en tant que livrable final, avec outputFiles déclaré
-- sur la tâche Kestra correspondante.
-- ============================================================

CREATE OR REPLACE TABLE vins_ordinaires AS SELECT * FROM read_csv_auto('vins_ordinaires.csv');

COPY vins_ordinaires TO 'vins_ordinaires_final.csv' (HEADER, DELIMITER ',');
